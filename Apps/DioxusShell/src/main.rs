use std::{
    env, fs,
    io::{Read, Write},
    net::TcpStream,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::OnceLock,
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use dioxus::prelude::*;

static STARTED_AT: OnceLock<Instant> = OnceLock::new();
static WEBUI_URL: OnceLock<String> = OnceLock::new();
static SHOULD_EXIT_ON_READY: OnceLock<bool> = OnceLock::new();

fn main() {
    let started_at = Instant::now();
    let _ = STARTED_AT.set(started_at);
    print_metric("appSetupStarted");

    let runtime = match RuntimePaths::resolve() {
        Ok(runtime) => runtime,
        Err(error) => {
            eprintln!("error={error}");
            std::process::exit(1);
        }
    };

    let mut backend = match launch_node_backend(&runtime) {
        Ok(backend) => backend,
        Err(error) => {
            eprintln!("error={error}");
            std::process::exit(1);
        }
    };

    if wait_for_manifest(&runtime.host, backend.port).is_err() {
        terminate_backend(&mut backend.child);
        eprintln!("error=Timed out waiting for WebUI manifest endpoint");
        std::process::exit(1);
    }
    print_metric("serverManifestReady");

    let webui_url = format!("http://{}:{}/", runtime.host, backend.port);
    let _ = WEBUI_URL.set(webui_url);
    let _ = SHOULD_EXIT_ON_READY.set(should_exit_on_ready());

    dioxus::LaunchBuilder::desktop().launch(App);
    terminate_backend(&mut backend.child);
}

#[component]
fn App() -> Element {
    let mut reported_window = use_signal(|| false);
    let mut reported_navigation = use_signal(|| false);
    let mut reported_render = use_signal(|| false);
    let webui_url = WEBUI_URL
        .get()
        .cloned()
        .unwrap_or_else(|| "http://127.0.0.1:8787/".to_string());

    if !*reported_window.read() {
        print_metric("windowShown");
        reported_window.set(true);
    }

    rsx! {
        style { {"
            html, body, #main {
                margin: 0;
                padding: 0;
                width: 100%;
                height: 100%;
                overflow: hidden;
                background: #111827;
            }
        "} }
        iframe {
            id: "main",
            src: "{webui_url}",
            border: "0",
            width: "100%",
            height: "100%",
            onload: move |_| {
                if !*reported_navigation.read() {
                    print_metric("webNavigationDidFinish");
                    reported_navigation.set(true);
                }
                if !*reported_render.read() {
                    print_metric("webAppRendered");
                    reported_render.set(true);
                    if *SHOULD_EXIT_ON_READY.get().unwrap_or(&false) {
                        std::process::exit(0);
                    }
                }
            }
        }
    }
}

struct RuntimePaths {
    root: PathBuf,
    node_path: String,
    server_script: PathBuf,
    bundle_root: PathBuf,
    host: String,
    port: u16,
}

struct BackendProcess {
    child: Child,
    port: u16,
}

impl RuntimePaths {
    fn resolve() -> Result<Self, String> {
        let host = env::var("GFC_HOST").unwrap_or_else(|_| "127.0.0.1".to_string());
        let port = configured_port()?;
        let root = runtime_root()?;
        let node_path = node_path(&root)?;
        let server_script = root.join("WebUI/dist/server/main.js");
        let bundle_root = bundle_root(&root);

        if !server_script.exists() {
            return Err(format!(
                "Missing WebUI server script: {}",
                server_script.display()
            ));
        }
        if !bundle_root.exists() {
            return Err(format!("Missing bundle: {}", bundle_root.display()));
        }

        Ok(Self {
            root,
            node_path,
            server_script,
            bundle_root,
            host,
            port,
        })
    }
}

fn configured_port() -> Result<u16, String> {
    match env::var("GFC_PORT") {
        Ok(value) if !value.trim().is_empty() => value
            .parse::<u16>()
            .map_err(|_| format!("Invalid GFC_PORT: {value}")),
        _ => Ok(0),
    }
}

fn runtime_root() -> Result<PathBuf, String> {
    if let Ok(value) = env::var("GFC_REPO_ROOT") {
        return Ok(PathBuf::from(value));
    }

    if let Ok(exe) = env::current_exe() {
        if let Some(parent) = exe.parent() {
            let server = parent.join("WebUI/dist/server/main.js");
            if server.exists() {
                return Ok(parent.to_path_buf());
            }
        }
    }

    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .map(Path::to_path_buf)
        .ok_or_else(|| "Could not resolve repository root".to_string())
}

fn node_path(root: &Path) -> Result<String, String> {
    if let Ok(path) = env::var("GFC_NODE_PATH") {
        if !path.trim().is_empty() {
            return Ok(path);
        }
    }

    let bundled = root.join(if cfg!(windows) {
        "node/node.exe"
    } else {
        "node/bin/node"
    });
    if bundled.exists() {
        return Ok(child_process_path(&bundled));
    }

    if cfg!(debug_assertions) {
        return Ok("node".to_string());
    }

    Err(format!(
        "Bundled Node runtime not found: {}",
        bundled.display()
    ))
}

fn bundle_root(root: &Path) -> PathBuf {
    if let Ok(path) = env::var("GFC_BUNDLE") {
        if !path.trim().is_empty() {
            return PathBuf::from(path);
        }
    }
    root.join("Examples/WGSExtract")
}

fn launch_node_backend(paths: &RuntimePaths) -> Result<BackendProcess, String> {
    let port_file = if paths.port == 0 {
        Some(port_file_path())
    } else {
        None
    };

    let mut command = Command::new(&paths.node_path);
    command
        .current_dir(child_process_path(&paths.root))
        .arg(child_process_path(&paths.server_script))
        .arg("--port")
        .arg(paths.port.to_string())
        .arg("--host")
        .arg(&paths.host)
        .arg("--bundle")
        .arg(child_process_path(&paths.bundle_root))
        .env("GFC_PARENT_PID", std::process::id().to_string())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    if let Some(port_file) = &port_file {
        command.env("GFC_PORT_FILE", child_process_path(port_file));
    }

    let mut child = command
        .spawn()
        .map_err(|error| format!("Failed to launch Node backend: {error}"))?;
    println!("node_pid={}", child.id());
    print_metric("nodeProcessStarted");

    let port = if let Some(port_file) = port_file {
        match wait_for_assigned_port(&port_file) {
            Ok(port) => port,
            Err(error) => {
                terminate_backend(&mut child);
                return Err(error);
            }
        }
    } else {
        paths.port
    };

    Ok(BackendProcess { child, port })
}

fn port_file_path() -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0_u128, |d| d.as_nanos());
    env::temp_dir().join(format!("gui-for-cli-dioxus-{nanos}.port"))
}

fn wait_for_assigned_port(path: &Path) -> Result<u16, String> {
    let deadline = Instant::now() + Duration::from_secs(15);
    while Instant::now() < deadline {
        if let Ok(contents) = fs::read_to_string(path) {
            if let Ok(port) = contents.trim().parse::<u16>() {
                let _ = fs::remove_file(path);
                return Ok(port);
            }
        }
        thread::sleep(Duration::from_millis(25));
    }
    Err(format!(
        "Timed out waiting for WebUI server port file: {}",
        path.display()
    ))
}

fn wait_for_manifest(host: &str, port: u16) -> Result<(), ()> {
    let deadline = Instant::now() + Duration::from_secs(15);
    while Instant::now() < deadline {
        if http_get_ok(host, port, "/api/manifest") {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(25));
    }
    Err(())
}

fn http_get_ok(host: &str, port: u16, path: &str) -> bool {
    let Ok(mut stream) = TcpStream::connect((host, port)) else {
        return false;
    };
    let timeout = Some(Duration::from_millis(250));
    if stream.set_read_timeout(timeout).is_err() || stream.set_write_timeout(timeout).is_err() {
        return false;
    }
    let request = format!("GET {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n");
    if stream.write_all(request.as_bytes()).is_err() {
        return false;
    }
    let mut response = [0_u8; 64];
    let Ok(count) = stream.read(&mut response) else {
        return false;
    };
    response[..count].starts_with(b"HTTP/1.1 200") || response[..count].starts_with(b"HTTP/1.0 200")
}

fn terminate_backend(child: &mut Child) {
    let _ = child.kill();
    let _ = child.wait();
}

fn child_process_path(path: &Path) -> String {
    let value = path.to_string_lossy();
    if cfg!(windows) {
        value.strip_prefix(r"\\?\").unwrap_or(&value).to_string()
    } else {
        value.into_owned()
    }
}

fn should_exit_on_ready() -> bool {
    matches!(
        env::var("GFC_BENCH_EXIT_AFTER_READY")
            .unwrap_or_default()
            .to_ascii_lowercase()
            .as_str(),
        "1" | "true" | "yes" | "on"
    )
}

fn print_metric(name: &str) {
    let started = STARTED_AT.get().copied().unwrap_or_else(Instant::now);
    let milliseconds = started.elapsed().as_secs_f64() * 1_000.0;
    println!("metric {name}_ms={milliseconds:.1}");
    let _ = std::io::stdout().flush();
}
