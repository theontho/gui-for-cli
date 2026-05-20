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

use tauri::{
    menu::{MenuBuilder, MenuItemBuilder, PredefinedMenuItem, SubmenuBuilder},
    Manager, WebviewUrl, WebviewWindowBuilder,
};

static NODE_PID: AtomicI32 = AtomicI32::new(0);
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const MENU_ZOOM_IN: &str = "view.zoom_in";
const MENU_ZOOM_OUT: &str = "view.zoom_out";
const MENU_ZOOM_RESET: &str = "view.zoom_reset";

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
        .manage(backend)
        .setup(move |app| {
            app.set_menu(build_app_menu(app)?)?;
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
                  window.__GUI_FOR_CLI_TAURI__ = true;
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
        .on_menu_event(|app, event| {
            let action = match event.id().as_ref() {
                MENU_ZOOM_IN => Some("in"),
                MENU_ZOOM_OUT => Some("out"),
                MENU_ZOOM_RESET => Some("reset"),
                _ => None,
            };
            let Some(action) = action else {
                return;
            };
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.eval(&format!(
                    "window.dispatchEvent(new CustomEvent('gui-for-cli-text-zoom', {{ detail: {{ action: '{action}' }} }}));"
                ));
            }
        })
        .run(tauri::generate_context!())
        .expect("failed to run GUI for CLI WebUI Tauri app");
}

fn build_app_menu<R: tauri::Runtime>(
    app: &tauri::App<R>,
) -> Result<tauri::menu::Menu<R>, Box<dyn std::error::Error>> {
    let mut menu = MenuBuilder::new(app);

    #[cfg(target_os = "macos")]
    {
        let app_submenu = SubmenuBuilder::new(app, app_name(app))
            .item(&PredefinedMenuItem::about(app, None, None)?)
            .separator()
            .item(&PredefinedMenuItem::services(app, None)?)
            .separator()
            .item(&PredefinedMenuItem::hide(app, None)?)
            .item(&PredefinedMenuItem::hide_others(app, None)?)
            .item(&PredefinedMenuItem::show_all(app, None)?)
            .separator()
            .item(&PredefinedMenuItem::quit(app, None)?)
            .build()?;
        menu = menu.item(&app_submenu);
    }

    let edit_submenu = SubmenuBuilder::new(app, "Edit")
        .item(&PredefinedMenuItem::cut(app, None)?)
        .item(&PredefinedMenuItem::copy(app, None)?)
        .item(&PredefinedMenuItem::paste(app, None)?)
        .item(&PredefinedMenuItem::select_all(app, None)?)
        .build()?;
    let view_submenu = SubmenuBuilder::new(app, "View")
        .item(
            &MenuItemBuilder::with_id(MENU_ZOOM_IN, "Zoom In")
                .accelerator("CmdOrCtrl+=")
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id(MENU_ZOOM_OUT, "Zoom Out")
                .accelerator("CmdOrCtrl+-")
                .build(app)?,
        )
        .item(
            &MenuItemBuilder::with_id(MENU_ZOOM_RESET, "Actual Size")
                .accelerator("CmdOrCtrl+0")
                .build(app)?,
        )
        .build()?;

    menu = menu.item(&edit_submenu).item(&view_submenu);

    Ok(menu.build()?)
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

fn app_name<R: tauri::Runtime>(app: &tauri::App<R>) -> String {
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
    if cfg!(debug_assertions) {
        command.env("GUI_FOR_CLI_DEBUG_PLATFORM_BADGE", "🕸️");
    }
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
