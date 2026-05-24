#![cfg_attr(
    all(not(debug_assertions), not(feature = "bench-console")),
    windows_subsystem = "windows"
)]

use std::{
    collections::HashMap,
    env,
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{
        atomic::{AtomicI32, Ordering},
        Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

use tauri::menu::{Menu, MenuItem, Submenu};
use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_updater::UpdaterExt;

static NODE_PID: AtomicI32 = AtomicI32::new(0);
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const CHECK_FOR_UPDATES_MENU_ID: &str = "check-for-updates";

struct BackendState {
    child: Child,
    port: u16,
}

struct BackendProcess(Arc<Mutex<Option<BackendState>>>);

impl BackendProcess {
    fn terminate(&self) {
        let Ok(mut state) = self.0.lock() else {
            return;
        };
        if let Some(mut state) = state.take() {
            let _ = request_backend_shutdown(state.port);
            let deadline = Instant::now() + Duration::from_secs(5);
            loop {
                match state.child.try_wait() {
                    Ok(Some(_)) => break,
                    Ok(None) if Instant::now() < deadline => {
                        thread::sleep(Duration::from_millis(50))
                    }
                    _ => {
                        let _ = state.child.kill();
                        let _ = state.child.wait();
                        break;
                    }
                }
            }
            NODE_PID.store(0, Ordering::SeqCst);
        }
    }
}

impl Drop for BackendProcess {
    fn drop(&mut self) {
        self.terminate();
    }
}

fn main() {
    #[cfg(unix)]
    unsafe {
        libc::signal(
            libc::SIGTERM,
            handle_signal as *const () as libc::sighandler_t,
        );
        libc::signal(
            libc::SIGINT,
            handle_signal as *const () as libc::sighandler_t,
        );
    }

    let started_at = Instant::now();
    let backend = BackendProcess(Arc::new(Mutex::new(None)));
    let backend_for_setup = backend.0.clone();

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .menu(|app| app_menu(app))
        .on_menu_event(|app, event| {
            if event.id().as_ref() == CHECK_FOR_UPDATES_MENU_ID {
                check_for_updates(app.clone());
            }
        })
        .manage(backend)
        .setup(move |app| {
            print_metric(started_at, "appSetupStarted");
            let paths = AppPaths::resolve(app)?;
            let port = free_port()?;
            let ready_listener = TcpListener::bind(("127.0.0.1", 0))?;
            let ready_port = ready_listener.local_addr()?.port();
            let picker_listener = TcpListener::bind(("127.0.0.1", 0))?;
            let picker_port = picker_listener.local_addr()?.port();
            start_native_picker_listener(picker_listener);
            let child = launch_node_backend(&paths, port, picker_port)?;
            let node_pid = child.id() as i32;
            NODE_PID.store(node_pid, Ordering::SeqCst);
            println!("node_pid={node_pid}");
            *backend_for_setup
                .lock()
                .map_err(|_| "Backend process lock was poisoned")? = Some(BackendState { child, port });
            print_metric(started_at, "nodeProcessStarted");

            wait_for_server_root(port)?;
            print_metric(started_at, "serverRootReady");

            start_render_ready_listener(ready_listener, started_at);
            let init_script = format!(
                r##"
                (() => {{
                  const readyPort = {ready_port};
                  const started = performance.now();
                  let reported = false;
                  const notify = () => {{
                    if (reported) {{
                      return;
                    }}
                    const app = document.querySelector("#app");
                    if (app && app.dataset.state === "ready" && document.title) {{
                      reported = true;
                      observer.disconnect();
                      fetch(`http://127.0.0.1:${{readyPort}}/ready?ms=${{performance.now() - started}}`, {{ mode: "no-cors" }}).catch(() => {{}});
                    }}
                  }};
                  const observer = new MutationObserver(notify);
                  observer.observe(document.documentElement, {{
                    attributes: true,
                    childList: true,
                    subtree: true,
                    attributeFilter: ["data-state"]
                  }});
                  window.addEventListener("gui-for-cli-rendered", notify);
                  document.addEventListener("DOMContentLoaded", notify);
                  window.addEventListener("load", notify);
                }})();
                "##
            );
            let url = format!("http://127.0.0.1:{port}/")
                .parse()
                .map_err(|error| format!("Invalid WebUI URL: {error}"))?;
            let window = WebviewWindowBuilder::new(app, "main", WebviewUrl::External(url))
                .title(app_name(app))
                .inner_size(1200.0, 800.0)
                .initialization_script(&init_script)
                .on_page_load(move |_window, _payload| {
                    print_metric(started_at, "webNavigationDidFinish");
                })
                .build()?;
            window.show()?;
            if std::env::var("GFC_BENCHMARK_PRESERVE_FOCUS").as_deref() != Ok("1") {
                window.set_focus()?;
            }
            print_metric(started_at, "windowShown");
            Ok(())
        })
        .on_window_event(|window, event| {
            if matches!(event, tauri::WindowEvent::CloseRequested { .. }) {
                let app = window.app_handle();
                app.state::<BackendProcess>().terminate();
                app.exit(0);
            }
        })
        .run(tauri::generate_context!())
        .expect("failed to run GUI for CLI WebUI Tauri app");
}

fn app_menu<R: tauri::Runtime>(app: &tauri::AppHandle<R>) -> tauri::Result<Menu<R>> {
    let menu = Menu::default(app)?;
    let check_for_updates = MenuItem::with_id(
        app,
        CHECK_FOR_UPDATES_MENU_ID,
        "Check for Updates...",
        true,
        None::<&str>,
    )?;
    let updates = Submenu::with_items(app, "Updates", true, &[&check_for_updates])?;
    menu.append(&updates)?;
    Ok(menu)
}

fn check_for_updates<R: tauri::Runtime>(app: tauri::AppHandle<R>) {
    tauri::async_runtime::spawn(async move {
        let update = match app.updater() {
            Ok(updater) => match updater.check().await {
                Ok(update) => update,
                Err(error) => {
                    show_update_message(
                        &app,
                        "Update Check Failed",
                        &format!("Could not check for updates: {error}"),
                        MessageDialogKind::Error,
                    );
                    return;
                }
            },
            Err(error) => {
                show_update_message(
                    &app,
                    "Updates Not Configured",
                    &format!("This build is not configured for updates: {error}"),
                    MessageDialogKind::Warning,
                );
                return;
            }
        };

        let Some(update) = update else {
            show_update_message(
                &app,
                "No Updates Available",
                "You are already running the latest version.",
                MessageDialogKind::Info,
            );
            return;
        };

        let prompt = format!(
            "Version {} is available. Download, install, and restart now?",
            update.version
        );
        let prompt_app = app.clone();
        let accepted = match tauri::async_runtime::spawn_blocking(move || {
            prompt_app
                .dialog()
                .message(prompt)
                .title("Update Available")
                .kind(MessageDialogKind::Info)
                .buttons(MessageDialogButtons::OkCancelCustom(
                    "Install and Restart".into(),
                    "Not Now".into(),
                ))
                .blocking_show()
        })
        .await
        {
            Ok(accepted) => accepted,
            Err(error) => {
                show_update_message(
                    &app,
                    "Update Check Failed",
                    &format!("Could not show the update prompt: {error}"),
                    MessageDialogKind::Error,
                );
                return;
            }
        };
        if !accepted {
            return;
        }

        match update.download_and_install(|_, _| {}, || {}).await {
            Ok(()) => {
                app.request_restart();
            }
            Err(error) => {
                show_update_message(
                    &app,
                    "Update Failed",
                    &format!("Could not install the update: {error}"),
                    MessageDialogKind::Error,
                );
            }
        }
    });
}

fn show_update_message<R: tauri::Runtime>(
    app: &tauri::AppHandle<R>,
    title: &str,
    message: &str,
    kind: MessageDialogKind,
) {
    app.dialog()
        .message(message)
        .title(title)
        .kind(kind)
        .buttons(MessageDialogButtons::Ok)
        .show(|_| {});
}

#[cfg(unix)]
extern "C" fn handle_signal(_signal: libc::c_int) {
    let pid = NODE_PID.load(Ordering::SeqCst);
    if pid > 0 {
        unsafe {
            libc::kill(pid, libc::SIGTERM);
        }
    }
    std::process::exit(0);
}

struct AppPaths {
    repo_root: PathBuf,
    node_path: String,
    server_script: PathBuf,
    bundle_root: PathBuf,
    app_support_name: String,
}

impl AppPaths {
    fn resolve(app: &tauri::App) -> Result<Self, Box<dyn std::error::Error>> {
        let resource_root = app.path().resource_dir()?;
        let repo_root = repo_root(resource_root)?;
        let node_path = node_path(&repo_root)?;
        let server_script = repo_root.join("platform/typescript/dist/web/src/server/main.js");
        let bundle_root = bundle_root(&repo_root);
        let app_support_name = app.config().identifier.clone();

        if !server_script.exists() {
            return Err(
                format!("WebUI server script not found: {}", server_script.display()).into(),
            );
        }
        if !bundle_root.exists() {
            return Err(format!("Bundle root not found: {}", bundle_root.display()).into());
        }

        Ok(Self {
            repo_root,
            node_path,
            server_script,
            bundle_root,
            app_support_name,
        })
    }
}

fn repo_root(resource_root: PathBuf) -> Result<PathBuf, Box<dyn std::error::Error>> {
    if cfg!(debug_assertions) {
        if let Some(path) = env::var_os("GUI_FOR_CLI_REPO_ROOT").map(PathBuf::from) {
            return Ok(path);
        }
        return Ok(Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .and_then(Path::parent)
            .and_then(Path::parent)
            .and_then(Path::parent)
            .ok_or("Could not resolve source repository root")?
            .to_path_buf());
    }
    Ok(resource_root)
}

fn node_path(repo_root: &Path) -> Result<String, Box<dyn std::error::Error>> {
    let bundled = repo_root.join(if cfg!(windows) {
        "node/node.exe"
    } else {
        "node/bin/node"
    });
    if bundled.exists() {
        return Ok(child_process_path(&bundled));
    }
    if !cfg!(debug_assertions) {
        return Err(format!("Bundled Node runtime not found: {}", bundled.display()).into());
    }
    if let Ok(path) = env::var("GUI_FOR_CLI_NODE_PATH") {
        return Ok(path);
    }
    if cfg!(unix) {
        for path in [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ] {
            if Path::new(path).exists() {
                return Ok(path.to_string());
            }
        }
    }
    Ok("node".to_string())
}

fn bundle_root(repo_root: &Path) -> PathBuf {
    if cfg!(debug_assertions) {
        if let Some(path) = env::var_os("GUI_FOR_CLI_BUNDLE").map(PathBuf::from) {
            return path;
        }
    }
    let embedded_bundle = repo_root.join("examples/EmbeddedBundle");
    if embedded_bundle.exists() {
        return embedded_bundle;
    }
    repo_root.join("examples/WGSExtract")
}

fn app_name(app: &tauri::App) -> String {
    app.config()
        .product_name
        .clone()
        .unwrap_or_else(|| "GUI for CLI WebUI".to_string())
}

fn launch_node_backend(
    paths: &AppPaths,
    port: u16,
    picker_port: u16,
) -> Result<Child, Box<dyn std::error::Error>> {
    let mut command = Command::new(&paths.node_path);
    command
        .current_dir(child_process_path(&paths.repo_root))
        .arg(child_process_path(&paths.server_script))
        .arg("--port")
        .arg(port.to_string())
        .arg("--host")
        .arg("127.0.0.1")
        .arg("--bundle")
        .arg(child_process_path(&paths.bundle_root))
        .env("GFC_PARENT_PID", std::process::id().to_string())
        .env("GUI_FOR_CLI_APP_SUPPORT_NAME", &paths.app_support_name)
        .env("GFC_NATIVE_PICKER_PORT", picker_port.to_string())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    #[cfg(windows)]
    command.creation_flags(CREATE_NO_WINDOW);
    Ok(command.spawn()?)
}

fn child_process_path(path: &Path) -> String {
    let value = path.to_string_lossy();
    if cfg!(windows) {
        value.strip_prefix(r"\\?\").unwrap_or(&value).to_string()
    } else {
        value.into_owned()
    }
}

fn wait_for_server_root(port: u16) -> Result<(), Box<dyn std::error::Error>> {
    let deadline = Instant::now() + Duration::from_secs(15);
    while Instant::now() < deadline {
        if http_get_ok(port, "/") {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(25));
    }
    Err("Timed out waiting for WebUI server root".into())
}

fn http_get_ok(port: u16, path: &str) -> bool {
    let Ok(mut stream) = TcpStream::connect(("127.0.0.1", port)) else {
        return false;
    };
    let request = format!("GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n");
    if stream.write_all(request.as_bytes()).is_err() {
        return false;
    }
    let mut response = [0; 64];
    let Ok(count) = stream.read(&mut response) else {
        return false;
    };
    response[..count].starts_with(b"HTTP/1.1 200") || response[..count].starts_with(b"HTTP/1.0 200")
}

fn request_backend_shutdown(port: u16) -> bool {
    let Ok(mut stream) = TcpStream::connect(("127.0.0.1", port)) else {
        return false;
    };
    let _ = stream.set_read_timeout(Some(Duration::from_millis(750)));
    let request =
        "POST /api/shutdown HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
    if stream.write_all(request.as_bytes()).is_err() {
        return false;
    }
    let mut response = [0; 64];
    let Ok(count) = stream.read(&mut response) else {
        return false;
    };
    response[..count].starts_with(b"HTTP/1.1 200") || response[..count].starts_with(b"HTTP/1.0 200")
}

fn start_render_ready_listener(listener: TcpListener, started_at: Instant) {
    thread::spawn(move || {
        if let Ok((mut stream, _)) = listener.accept() {
            let mut buffer = [0; 1024];
            let count = stream.read(&mut buffer).unwrap_or(0);
            let request = String::from_utf8_lossy(&buffer[..count]);
            if let Some(page_ms) = request
                .split_whitespace()
                .nth(1)
                .and_then(|path| path.split("ms=").nth(1))
                .and_then(|value| value.split('&').next())
            {
                println!("metric webAppRenderedInPage_ms={page_ms}");
            }
            print_metric(started_at, "webAppRendered");
            let _ = stream.write_all(
                b"HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            );
        }
    });
}

fn start_native_picker_listener(listener: TcpListener) {
    thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            thread::spawn(move || {
                handle_native_picker_request(stream);
            });
        }
    });
}

fn handle_native_picker_request(mut stream: TcpStream) {
    let mut buffer = [0; 4096];
    let count = stream.read(&mut buffer).unwrap_or(0);
    let request = String::from_utf8_lossy(&buffer[..count]);
    let Some(target) = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
    else {
        write_json_response(
            &mut stream,
            400,
            serde_json::json!({"error": "Invalid request"}),
        );
        return;
    };
    let Some(query) =
        target
            .strip_prefix("/pick?")
            .or_else(|| if target == "/pick" { Some("") } else { None })
    else {
        write_json_response(&mut stream, 404, serde_json::json!({"error": "Not found"}));
        return;
    };
    let values = parse_query(query);
    let kind = values.get("kind").map(String::as_str).unwrap_or("file");
    let title = values
        .get("title")
        .map(String::as_str)
        .unwrap_or(if kind == "directory" {
            "Choose directory"
        } else {
            "Choose file"
        });
    let default_path = values.get("defaultPath").map(String::as_str).unwrap_or("");
    match pick_native_path(kind, title, default_path) {
        Ok(Some(path)) => write_json_response(
            &mut stream,
            200,
            serde_json::json!({"path": child_process_path(&path), "kind": kind, "cancelled": false}),
        ),
        Ok(None) => write_json_response(
            &mut stream,
            200,
            serde_json::json!({"kind": kind, "cancelled": true}),
        ),
        Err(error) => write_json_response(
            &mut stream,
            400,
            serde_json::json!({"error": error.to_string()}),
        ),
    }
}

fn pick_native_path(
    kind: &str,
    title: &str,
    default_path: &str,
) -> Result<Option<PathBuf>, Box<dyn std::error::Error>> {
    let mut dialog = rfd::FileDialog::new().set_title(title);
    if !default_path.is_empty() {
        dialog = dialog.set_directory(default_path);
    }
    match kind {
        "directory" | "folder" => Ok(dialog.pick_folder()),
        "file" => Ok(dialog.pick_file()),
        _ => Err("Path picker kind must be file or directory.".into()),
    }
}

fn parse_query(query: &str) -> HashMap<String, String> {
    query
        .split('&')
        .filter(|part| !part.is_empty())
        .filter_map(|part| {
            let (key, value) = part.split_once('=').unwrap_or((part, ""));
            Some((percent_decode(key)?, percent_decode(value)?))
        })
        .collect()
}

fn percent_decode(value: &str) -> Option<String> {
    let bytes = value.as_bytes();
    let mut output = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'+' => {
                output.push(b' ');
                index += 1;
            }
            b'%' if index + 2 < bytes.len() => {
                let hex = std::str::from_utf8(&bytes[index + 1..index + 3]).ok()?;
                output.push(u8::from_str_radix(hex, 16).ok()?);
                index += 3;
            }
            byte => {
                output.push(byte);
                index += 1;
            }
        }
    }
    String::from_utf8(output).ok()
}

fn write_json_response(stream: &mut TcpStream, status: u16, body: serde_json::Value) {
    let reason = match status {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        _ => "Internal Server Error",
    };
    let payload = format!("{body}\n");
    let response = format!(
        "HTTP/1.1 {status} {reason}\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{payload}",
        payload.len()
    );
    let _ = stream.write_all(response.as_bytes());
}

fn free_port() -> Result<u16, std::io::Error> {
    let listener = TcpListener::bind(("127.0.0.1", 0))?;
    Ok(listener.local_addr()?.port())
}

fn print_metric(started_at: Instant, name: &str) {
    println!(
        "metric {name}_ms={:.1}",
        started_at.elapsed().as_secs_f64() * 1_000.0
    );
}
