#![cfg_attr(
    all(not(debug_assertions), not(feature = "bench-console")),
    windows_subsystem = "windows"
)]

use std::{
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

use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};

static NODE_PID: AtomicI32 = AtomicI32::new(0);

struct BackendProcess(Arc<Mutex<Option<Child>>>);

impl BackendProcess {
    fn terminate(&self) {
        let Ok(mut child) = self.0.lock() else {
            return;
        };
        if let Some(mut child) = child.take() {
            let _ = child.kill();
            let _ = child.wait();
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
            print_metric(started_at, "appSetupStarted");
            let paths = AppPaths::resolve(app)?;
            let port = free_port()?;
            let ready_listener = TcpListener::bind(("127.0.0.1", 0))?;
            let ready_port = ready_listener.local_addr()?.port();
            let child = launch_node_backend(&paths, port)?;
            let node_pid = child.id() as i32;
            NODE_PID.store(node_pid, Ordering::SeqCst);
            println!("node_pid={node_pid}");
            *backend_for_setup
                .lock()
                .map_err(|_| "Backend process lock was poisoned")? = Some(child);
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
                .title("GUI for CLI WebUI")
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
                window
                    .app_handle()
                    .state::<BackendProcess>()
                    .terminate();
            }
        })
        .run(tauri::generate_context!())
        .expect("failed to run GUI for CLI WebUI Tauri app");
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
}

impl AppPaths {
    fn resolve(app: &tauri::App) -> Result<Self, Box<dyn std::error::Error>> {
        let resource_root = app.path().resource_dir()?;
        let repo_root = repo_root(resource_root)?;
        let node_path = node_path(&repo_root)?;
        let server_script = repo_root.join("platform/typescript/dist/web/src/server/main.js");
        let bundle_root = bundle_root(&repo_root);

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
    repo_root.join("examples/WGSExtract")
}

fn launch_node_backend(paths: &AppPaths, port: u16) -> Result<Child, Box<dyn std::error::Error>> {
    let child = Command::new(&paths.node_path)
        .current_dir(child_process_path(&paths.repo_root))
        .arg(child_process_path(&paths.server_script))
        .arg("--port")
        .arg(port.to_string())
        .arg("--host")
        .arg("127.0.0.1")
        .arg("--bundle")
        .arg(child_process_path(&paths.bundle_root))
        .env("GFC_PARENT_PID", std::process::id().to_string())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    Ok(child)
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
