#![cfg_attr(
    all(not(debug_assertions), not(feature = "bench-console")),
    windows_subsystem = "windows"
)]

use std::{
    env, fs,
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

use app_update::{
    check_for_updates, env_duration_seconds, env_flag, gfc_update_check, gfc_update_download,
    gfc_update_install, AUTO_ACCEPT_UPDATE_ENV, AUTO_UPDATE_ACTION_DELAY_SECONDS_ENV,
    AUTO_UPDATE_DELAY_SECONDS_ENV, AUTO_UPDATE_ENV, E2E_STEP_DELAY_SECONDS_ENV,
};
use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};

mod app_update;
mod menu;
mod native_picker;
mod update_e2e_overlay;

use menu::{
    app_menu, app_name, request_about, request_load_bundle, ABOUT_MENU_ID,
    CHECK_FOR_UPDATES_MENU_ID, LOAD_BUNDLE_MENU_ID,
};
use native_picker::start_native_picker_listener;

static NODE_PID: AtomicI32 = AtomicI32::new(0);
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const PORT_FILE_ENV: &str = "GFC_PORT_FILE";

struct BackendState {
    child: Child,
    port: u16,
}

pub(crate) struct BackendProcess(Arc<Mutex<Option<BackendState>>>);

impl BackendProcess {
    pub(crate) fn terminate(&self) {
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
        .invoke_handler(tauri::generate_handler![
            gfc_update_check,
            gfc_update_download,
            gfc_update_install
        ])
        .menu(|app| app_menu(app))
        .on_menu_event(|app, event| {
            match event.id().as_ref() {
                ABOUT_MENU_ID => request_about(app),
                CHECK_FOR_UPDATES_MENU_ID => check_for_updates(app.clone()),
                LOAD_BUNDLE_MENU_ID => request_load_bundle(app),
                _ => {}
            }
        })
        .manage(backend)
        .setup(move |app| {
            print_metric(started_at, "appSetupStarted");
            let paths = AppPaths::resolve(app)?;
            let application_name = app_name(app);
            let application_version = app_version(app);
            let port = free_port()?;
            let ready_listener = TcpListener::bind(("127.0.0.1", 0))?;
            let ready_port = ready_listener.local_addr()?.port();
            let picker_listener = TcpListener::bind(("127.0.0.1", 0))?;
            let picker_port = picker_listener.local_addr()?.port();
            start_native_picker_listener(picker_listener);
            let child = launch_node_backend(
                &paths,
                port,
                picker_port,
                &application_name,
                &application_version,
            )?;
            let node_pid = child.id() as i32;
            NODE_PID.store(node_pid, Ordering::SeqCst);
            println!("node_pid={node_pid}");
            *backend_for_setup
                .lock()
                .map_err(|_| "Backend process lock was poisoned")? = Some(BackendState { child, port });
            print_metric(started_at, "nodeProcessStarted");

            wait_for_server_root(port)?;
            print_metric(started_at, "serverRootReady");
            write_port_file(port)?;

            start_render_ready_listener(ready_listener, started_at);
            let overlay_script = update_e2e_overlay::script(&application_name, &application_version);
            let auto_update = env_flag(AUTO_UPDATE_ENV);
            let auto_accept_update = env_flag(AUTO_ACCEPT_UPDATE_ENV);
            let auto_update_delay_seconds =
                env_duration_seconds(AUTO_UPDATE_DELAY_SECONDS_ENV).as_secs();
            let auto_update_action_delay_seconds =
                if env::var_os(AUTO_UPDATE_ACTION_DELAY_SECONDS_ENV).is_some() {
                    env_duration_seconds(AUTO_UPDATE_ACTION_DELAY_SECONDS_ENV)
                } else {
                    env_duration_seconds(E2E_STEP_DELAY_SECONDS_ENV)
                }
                .as_secs();
            let init_script = format!(
                r##"
                (() => {{
                  window.__GUI_FOR_CLI_TAURI__ = true;
                  const readyPort = {ready_port};
                  window.GUI_FOR_CLI_APPLICATION_NAME = {application_name:?};
                  window.GUI_FOR_CLI_APPLICATION_VERSION = {application_version:?};
                  window.GUI_FOR_CLI_AUTO_UPDATE = {auto_update:?};
                  window.GUI_FOR_CLI_AUTO_ACCEPT_UPDATE = {auto_accept_update:?};
                  window.GUI_FOR_CLI_AUTO_UPDATE_DELAY_SECONDS = {auto_update_delay_seconds};
                  window.GUI_FOR_CLI_AUTO_UPDATE_ACTION_DELAY_SECONDS = {auto_update_action_delay_seconds};
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
                {overlay_script}
                "##
            );
            let url = format!("http://127.0.0.1:{port}/")
                .parse()
                .map_err(|error| format!("Invalid WebUI URL: {error}"))?;
            let window = WebviewWindowBuilder::new(app, "main", WebviewUrl::External(url))
                .title(window_title(&application_name, &application_version))
                .inner_size(1200.0, 800.0)
                .initialization_script(&init_script)
                .on_document_title_changed(|window, title| {
                    let _ = window.set_title(&title);
                })
                .on_page_load(move |_window, _payload| {
                    print_metric(started_at, "webNavigationDidFinish");
                })
                .build()?;
            window.show()?;
            if std::env::var("GFC_BENCHMARK_PRESERVE_FOCUS").as_deref() != Ok("1") {
                window.set_focus()?;
            }
            print_metric(started_at, "windowShown");
            update_e2e_overlay::update(
                app.handle(),
                "App launched",
                &format!("Installed version: {application_version}"),
            );
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

fn write_port_file(port: u16) -> Result<(), Box<dyn std::error::Error>> {
    let Some(path) = env::var_os(PORT_FILE_ENV).map(PathBuf::from) else {
        return Ok(());
    };
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, format!("{port}\n"))?;
    Ok(())
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

fn app_version(app: &tauri::App) -> String {
    app.package_info().version.to_string()
}

fn window_title(application_name: &str, application_version: &str) -> String {
    format!("{application_name} {application_version}")
}

fn launch_node_backend(
    paths: &AppPaths,
    port: u16,
    picker_port: u16,
    application_name: &str,
    application_version: &str,
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
        .env("GUI_FOR_CLI_APPLICATION_NAME", application_name)
        .env("GUI_FOR_CLI_APPLICATION_VERSION", application_version)
        .env("GFC_NATIVE_PICKER_PORT", picker_port.to_string())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    #[cfg(windows)]
    command.creation_flags(CREATE_NO_WINDOW);
    Ok(command.spawn()?)
}

pub(crate) fn child_process_path(path: &Path) -> String {
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
