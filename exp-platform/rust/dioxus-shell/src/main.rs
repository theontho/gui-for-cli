use std::{
    collections::BTreeMap,
    env, fs,
    io::{Read, Write},
    net::{TcpStream, ToSocketAddrs},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::OnceLock,
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use dioxus::prelude::*;
use dioxus_desktop::{Config, LogicalSize, WindowBuilder};
use serde_json::Value;

static STARTED_AT: OnceLock<Instant> = OnceLock::new();
static WEBUI_URL: OnceLock<String> = OnceLock::new();
static SHOULD_EXIT_ON_READY: OnceLock<bool> = OnceLock::new();
static BUNDLE_SUMMARY: OnceLock<BundleSummary> = OnceLock::new();

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
    let summary = load_bundle_summary(&runtime.bundle_root).unwrap_or_else(|error| {
        eprintln!("warning=Could not load bundle summary for native shell: {error}");
        BundleSummary::fallback()
    });
    let title = format!("GUI for CLI Dioxus · {}", summary.title);
    let _ = BUNDLE_SUMMARY.set(summary);
    let _ = SHOULD_EXIT_ON_READY.set(should_exit_on_ready());

    dioxus::LaunchBuilder::desktop()
        .with_cfg(Config::new().with_window(
            WindowBuilder::new()
                .with_title(title)
                .with_inner_size(LogicalSize::new(1344.0, 864.0))
                .with_min_inner_size(LogicalSize::new(960.0, 640.0)),
        ))
        .launch(App);
    terminate_backend(&mut backend.child);
}

#[component]
fn App() -> Element {
    let desktop = dioxus_desktop::use_window();
    let mut selected_page = use_signal(|| 0usize);
    let mut reported_window = use_signal(|| false);
    let mut reported_navigation = use_signal(|| false);
    let mut reported_render = use_signal(|| false);
    let summary = BUNDLE_SUMMARY
        .get()
        .cloned()
        .unwrap_or_else(BundleSummary::fallback);
    let webui_url = WEBUI_URL
        .get()
        .cloned()
        .unwrap_or_else(|| "http://127.0.0.1:8787/".to_string());
    let selected_index = (*selected_page.read()).min(summary.pages.len().saturating_sub(1));
    let current_page = summary.pages.get(selected_index).cloned();

    if !*reported_window.read() {
        print_metric("windowShown");
        reported_window.set(true);
    }
    if !*reported_navigation.read() {
        print_metric("webNavigationDidFinish");
        reported_navigation.set(true);
    }
    if !*reported_render.read() {
        print_metric("webAppRendered");
        reported_render.set(true);
        if *SHOULD_EXIT_ON_READY.get().unwrap_or(&false) {
            desktop.close();
        }
    }

    rsx! {
        style { {"
            html, body, #main {
                margin: 0;
                padding: 0;
                width: 100%;
                height: 100%;
                background: #f3f4f6;
                color: #111827;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            }
            * { box-sizing: border-box; }
            .shell {
                display: grid;
                grid-template-columns: 320px minmax(0, 1fr);
                height: 100vh;
            }
            .sidebar {
                overflow: auto;
                padding: 22px 18px;
                color: white;
                background: linear-gradient(180deg, #111827 0%, #1f2937 100%);
            }
            .sidebar h1 {
                margin: 0 0 8px;
                font-size: 27px;
            }
            .sidebar p {
                margin: 0 0 18px;
                color: #d1d5db;
                line-height: 1.38;
            }
            .metric-row {
                display: grid;
                grid-template-columns: repeat(3, 1fr);
                gap: 8px;
                margin-bottom: 20px;
            }
            .metric {
                padding: 10px;
                border-radius: 12px;
                background: rgba(255,255,255,0.10);
                text-align: center;
            }
            .metric strong {
                display: block;
                font-size: 20px;
            }
            .page-button {
                display: block;
                width: 100%;
                margin: 6px 0;
                padding: 11px 12px;
                border: 0;
                border-radius: 12px;
                text-align: left;
                color: #e5e7eb;
                background: transparent;
                font: inherit;
                cursor: pointer;
            }
            .page-button.selected {
                color: #111827;
                background: #f9fafb;
                font-weight: 700;
            }
            .content {
                overflow: auto;
                padding: 28px;
            }
            .hero, .panel {
                margin-bottom: 18px;
                padding: 22px;
                border: 1px solid #e5e7eb;
                border-radius: 18px;
                background: white;
                box-shadow: 0 12px 32px rgba(15, 23, 42, 0.08);
            }
            .hero h2 {
                margin: 0 0 8px;
                font-size: 32px;
            }
            .hero p, .panel p {
                color: #4b5563;
                line-height: 1.5;
            }
            .two-col {
                display: grid;
                grid-template-columns: minmax(0, 1fr) minmax(260px, 0.45fr);
                gap: 18px;
            }
            .chip-row {
                display: flex;
                flex-wrap: wrap;
                gap: 8px;
            }
            .chip {
                padding: 8px 10px;
                border-radius: 999px;
                background: #eef2ff;
                color: #3730a3;
                font-weight: 600;
            }
            li {
                margin: 8px 0;
                line-height: 1.4;
            }
            .url {
                color: #2563eb;
                word-break: break-all;
            }
        "} }
        div { class: "shell",
            aside { class: "sidebar",
                h1 { "{summary.title}" }
                p { "{summary.summary}" }
                div { class: "metric-row",
                    div { class: "metric", strong { "{summary.pages.len()}" } span { "Pages" } }
                    div { class: "metric", strong { "{summary.control_count}" } span { "Controls" } }
                    div { class: "metric", strong { "{summary.action_count}" } span { "Actions" } }
                }
                for (index, page) in summary.pages.iter().enumerate() {
                    button {
                        key: "{page.id}",
                        class: if index == selected_index { "page-button selected" } else { "page-button" },
                        onclick: move |_| selected_page.set(index),
                        "{page.title}"
                    }
                }
            }
            main { class: "content",
                if let Some(page) = current_page {
                    section { class: "hero",
                        h2 { "{page.title}" }
                        p { "{page.summary}" }
                    }
                    div { class: "two-col",
                        section { class: "panel",
                            h3 { "Controls" }
                            ul {
                                for control in page.controls.iter().take(12) {
                                    li { "{control}" }
                                }
                            }
                        }
                        section { class: "panel",
                            h3 { "Actions" }
                            div { class: "chip-row",
                                for action in page.actions.iter().take(12) {
                                    span { class: "chip", "{action}" }
                                }
                            }
                        }
                    }
                    section { class: "panel",
                        h3 { "Backed by the Web UI server" }
                        p {
                            "The Dioxus desktop shell keeps the Web UI backend live at "
                            span { class: "url", "{webui_url}" }
                            " while rendering the benchmark bundle through native Dioxus components."
                        }
                    }
                }
            }
        }
    }
}

#[derive(Clone)]
struct BundleSummary {
    title: String,
    summary: String,
    pages: Vec<PageSummary>,
    control_count: usize,
    action_count: usize,
}

#[derive(Clone)]
struct PageSummary {
    id: String,
    title: String,
    summary: String,
    controls: Vec<String>,
    actions: Vec<String>,
}

impl BundleSummary {
    fn fallback() -> Self {
        Self {
            title: "GUI for CLI".to_string(),
            summary: "Bundle summary unavailable.".to_string(),
            pages: vec![PageSummary {
                id: "status".to_string(),
                title: "Status".to_string(),
                summary: "The Dioxus surface is running.".to_string(),
                controls: vec!["No controls loaded.".to_string()],
                actions: vec!["No actions loaded.".to_string()],
            }],
            control_count: 0,
            action_count: 0,
        }
    }
}

fn load_bundle_summary(bundle_root: &Path) -> Result<BundleSummary, String> {
    let strings = load_strings(bundle_root)?;
    let manifest_path = bundle_root.join("manifest.json");
    let manifest = read_json(&manifest_path)?;
    let title = localize(
        manifest
            .get("displayName")
            .and_then(Value::as_str)
            .unwrap_or("GUI for CLI"),
        &strings,
    );
    let summary = localize(
        manifest.get("summary").and_then(Value::as_str).unwrap_or(""),
        &strings,
    );
    let mut pages = Vec::new();

    for page_entry in manifest
        .get("pages")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let Some(page_file) = page_entry.as_str() else {
            continue;
        };
        let page = read_page_json(bundle_root, page_file)?;
        let mut controls = Vec::new();
        let mut actions = Vec::new();
        for section in page
            .get("sections")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            for control in section
                .get("controls")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
            {
                let label = control
                    .get("label")
                    .and_then(Value::as_str)
                    .or_else(|| control.get("id").and_then(Value::as_str))
                    .unwrap_or("Control");
                let kind = control.get("kind").and_then(Value::as_str).unwrap_or("input");
                controls.push(format!("{} · {}", localize(label, &strings), kind));
            }
            for action in section
                .get("actions")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
            {
                let title = action
                    .get("title")
                    .and_then(Value::as_str)
                    .or_else(|| action.get("id").and_then(Value::as_str))
                    .unwrap_or("Action");
                actions.push(localize(title, &strings));
            }
        }
        pages.push(PageSummary {
            id: page
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or(page_file)
                .to_string(),
            title: localize(
                page.get("title").and_then(Value::as_str).unwrap_or(page_file),
                &strings,
            ),
            summary: localize(
                page.get("summary").and_then(Value::as_str).unwrap_or(""),
                &strings,
            ),
            controls,
            actions,
        });
    }

    if pages.is_empty() {
        return Err("manifest did not resolve any pages".to_string());
    }

    let control_count = pages.iter().map(|page| page.controls.len()).sum();
    let action_count = pages.iter().map(|page| page.actions.len()).sum();
    Ok(BundleSummary {
        title,
        summary,
        pages,
        control_count,
        action_count,
    })
}

fn read_json(path: &Path) -> Result<Value, String> {
    let contents = fs::read_to_string(path).map_err(|error| format!("read {}: {error}", path.display()))?;
    serde_json::from_str(&contents).map_err(|error| format!("parse {}: {error}", path.display()))
}

fn read_page_json(bundle_root: &Path, page_file: &str) -> Result<Value, String> {
    let pages_root = bundle_root
        .join("pages")
        .canonicalize()
        .map_err(|error| format!("resolve bundle pages directory: {error}"))?;
    let page_path = pages_root
        .join(page_file)
        .canonicalize()
        .map_err(|error| format!("resolve page reference {page_file}: {error}"))?;
    if !page_path.starts_with(&pages_root) {
        return Err(format!(
            "page reference escapes bundle pages directory: {page_file}"
        ));
    }
    read_json(&page_path)
}

fn load_strings(bundle_root: &Path) -> Result<BTreeMap<String, String>, String> {
    let mut strings = BTreeMap::new();
    let strings_path = bundle_root.join("strings").join("strings.en.toml");
    let contents = fs::read_to_string(&strings_path)
        .map_err(|error| format!("read {}: {error}", strings_path.display()))?;
    for line in contents.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let Some((key, value)) = trimmed.split_once('=') else {
            continue;
        };
        strings.insert(unquote(key.trim()), unquote(value.trim()));
    }
    Ok(strings)
}

fn localize(value: &str, strings: &BTreeMap<String, String>) -> String {
    strings.get(value).cloned().unwrap_or_else(|| {
        value
            .split('.')
            .next_back()
            .filter(|segment| !segment.is_empty())
            .unwrap_or(value)
            .replace('-', " ")
    })
}

fn unquote(value: &str) -> String {
    let trimmed = value.trim();
    let unquoted = trimmed
        .strip_prefix('"')
        .and_then(|value| value.strip_suffix('"'))
        .unwrap_or(trimmed);
    unquoted
        .replace("\\\"", "\"")
        .replace("\\n", "\n")
        .replace("\\\\", "\\")
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
        let server_script = root.join("platform/typescript/dist/web/src/server/main.js");
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
            let server = parent.join("platform/typescript/dist/web/src/server/main.js");
            if server.exists() {
                return Ok(parent.to_path_buf());
            }
        }
    }

    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
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
    root.join("examples/WGSExtract")
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
    let timeout = Duration::from_millis(250);
    let Ok(addrs) = (host, port).to_socket_addrs() else {
        return false;
    };
    let mut stream = None;
    for addr in addrs {
        if let Ok(candidate) = TcpStream::connect_timeout(&addr, timeout) {
            stream = Some(candidate);
            break;
        }
    }
    let Some(mut stream) = stream else {
        return false;
    };
    let timeout = Some(timeout);
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
