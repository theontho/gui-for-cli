use anyhow::{Context, Result, anyhow};
use serde::Deserialize;
use serde_json::Value;
use slint::{ComponentHandle, ModelRc, SharedString, VecModel};
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Instant;

slint::slint! {
    import { Button, ScrollView } from "std-widgets.slint";

    export struct PageTab {
        title: string,
    }

    export component AppWindow inherits Window {
        in property <string> window-title;
        in property <string> bundle-summary;
        in property <string> page-title;
        in property <string> page-summary;
        in property <string> page-body;
        in property <[PageTab]> pages;
        callback page-selected(int);

        title: root.window-title;
        width: 1120px;
        height: 720px;
        background: #f6f7fb;

        HorizontalLayout {
            padding: 16px;
            spacing: 16px;

            Rectangle {
                width: 260px;
                background: #ffffff;
                border-color: #d7dbe7;
                border-radius: 12px;

                VerticalLayout {
                    padding: 14px;
                    spacing: 10px;

                    Text {
                        text: root.window-title;
                        font-size: 22px;
                        font-weight: 700;
                        color: #1c2333;
                    }

                    Text {
                        text: root.bundle-summary;
                        wrap: word-wrap;
                        color: #566070;
                    }

                    Rectangle { height: 1px; background: #e4e7ef; }

                    ScrollView {
                        viewport-width: 232px;

                        VerticalLayout {
                            spacing: 8px;

                            for page[index] in root.pages : Button {
                                text: page.title;
                                clicked => {
                                    root.page-selected(index);
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                background: #ffffff;
                border-color: #d7dbe7;
                border-radius: 12px;

                VerticalLayout {
                    padding: 18px;
                    spacing: 12px;

                    Text {
                        text: root.page-title;
                        font-size: 26px;
                        font-weight: 700;
                        color: #1c2333;
                    }

                    Text {
                        text: root.page-summary;
                        wrap: word-wrap;
                        color: #566070;
                    }

                    Rectangle { height: 1px; background: #e4e7ef; }

                    ScrollView {
                        Text {
                            text: root.page-body;
                            wrap: word-wrap;
                            color: #263044;
                            font-size: 15px;
                        }
                    }
                }
            }
        }
    }
}

#[derive(Debug, Default)]
struct Args {
    bundle: PathBuf,
    repo_root: PathBuf,
    locale: String,
    benchmark: bool,
    once: bool,
}

#[derive(Debug, Deserialize)]
struct Manifest {
    id: String,
    #[serde(rename = "displayName")]
    display_name: Option<String>,
    summary: Option<String>,
    #[serde(default)]
    pages: Vec<Value>,
}

#[derive(Debug, Deserialize)]
struct Page {
    id: String,
    title: Option<String>,
    summary: Option<String>,
    #[serde(default)]
    sections: Vec<Section>,
}

#[derive(Debug, Deserialize)]
struct Section {
    id: String,
    title: Option<String>,
    subtitle: Option<String>,
    #[serde(default)]
    controls: Vec<Control>,
    #[serde(default)]
    actions: Vec<Action>,
}

#[derive(Debug, Deserialize)]
struct Control {
    id: String,
    label: Option<String>,
    kind: Option<String>,
    value: Option<Value>,
    tooltip: Option<String>,
    #[serde(default)]
    options: Vec<OptionItem>,
    #[serde(rename = "rowActions", default)]
    row_actions: Vec<Action>,
}

#[derive(Debug, Deserialize)]
struct OptionItem {
    id: String,
    title: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Action {
    id: String,
    title: Option<String>,
    tooltip: Option<String>,
    command: Option<Command>,
}

#[derive(Debug, Deserialize)]
struct Command {
    executable: Option<String>,
    #[serde(default)]
    arguments: Vec<String>,
    #[serde(rename = "optionalArguments", default)]
    optional_arguments: Vec<Vec<String>>,
}

#[derive(Debug)]
struct BundleView {
    title: String,
    summary: String,
    pages: Vec<PageView>,
}

#[derive(Debug)]
struct PageView {
    title: String,
    summary: String,
    body: String,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("gui-for-cli-slint: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let started = Instant::now();
    let args = parse_args()?;
    let bundle = load_bundle(&args.bundle, &args.repo_root, &args.locale)?;
    let loaded_ms = started.elapsed().as_secs_f64() * 1000.0;

    let page_tabs = bundle
        .pages
        .iter()
        .map(|page| PageTab {
            title: page.title.as_str().into(),
        })
        .collect::<Vec<_>>();
    let pages = Rc::new(bundle.pages);
    let first_page = pages.first().ok_or_else(|| anyhow!("bundle has no pages"))?;

    let ui = AppWindow::new().context("create Slint window")?;
    ui.set_window_title(bundle.title.as_str().into());
    ui.set_bundle_summary(bundle.summary.as_str().into());
    ui.set_pages(ModelRc::new(Rc::new(VecModel::from(page_tabs))));
    set_page(&ui, first_page);

    let ui_weak = ui.as_weak();
    let pages_for_callback = pages.clone();
    ui.on_page_selected(move |index| {
        if let Some(ui) = ui_weak.upgrade() {
            if let Some(page) = pages_for_callback.get(index.max(0) as usize) {
                set_page(&ui, page);
            }
        }
    });

    let ready_ms = started.elapsed().as_secs_f64() * 1000.0;
    if args.benchmark {
        println!(
            "gfc-slint benchmark bundle_loaded_ms={loaded_ms:.1} ui_ready_ms={ready_ms:.1} pages={}",
            pages.len()
        );
    }

    if args.once {
        return Ok(());
    }

    ui.run().context("run Slint window")
}

fn parse_args() -> Result<Args> {
    let current_dir = env::current_dir().context("read current directory")?;
    let repo_root = find_repo_root(&current_dir).unwrap_or(current_dir);
    let mut args = Args {
        bundle: repo_root.join("Examples").join("WGSExtract"),
        repo_root,
        locale: "en".to_string(),
        benchmark: false,
        once: false,
    };

    let mut raw = env::args().skip(1);
    while let Some(argument) = raw.next() {
        match argument.as_str() {
            "--bundle" => {
                args.bundle = PathBuf::from(
                    raw.next()
                        .ok_or_else(|| anyhow!("--bundle requires a path"))?,
                );
            }
            "--repo-root" => {
                args.repo_root = PathBuf::from(
                    raw.next()
                        .ok_or_else(|| anyhow!("--repo-root requires a path"))?,
                );
            }
            "--locale" => {
                args.locale = raw
                    .next()
                    .ok_or_else(|| anyhow!("--locale requires a locale code"))?;
            }
            "--benchmark" => args.benchmark = true,
            "--once" => args.once = true,
            "--help" | "-h" => {
                print_help();
                std::process::exit(0);
            }
            _ => return Err(anyhow!("unknown argument: {argument}")),
        }
    }

    if args.bundle.is_relative() {
        args.bundle = args.repo_root.join(&args.bundle);
    }
    Ok(args)
}

fn print_help() {
    println!(
        "Usage: gui-for-cli-slint [--bundle PATH] [--repo-root PATH] [--locale CODE] [--benchmark] [--once]"
    );
}

fn find_repo_root(start: &Path) -> Option<PathBuf> {
    start
        .ancestors()
        .find(|candidate| candidate.join("Examples").join("WGSExtract").exists())
        .map(Path::to_path_buf)
}

fn load_bundle(bundle_root: &Path, repo_root: &Path, locale: &str) -> Result<BundleView> {
    let manifest_path = bundle_root.join("manifest.json");
    let manifest: Manifest = read_json(&manifest_path)?;
    let strings = load_strings(bundle_root, repo_root, locale)?;
    let mut pages = Vec::new();

    for page_value in &manifest.pages {
        let page = match page_value {
            Value::String(page_file) => {
                if page_file.contains('/') || page_file.contains('\\') || page_file.contains("..") {
                    return Err(anyhow!("invalid page file name: {page_file}"));
                }
                read_json(&bundle_root.join("pages").join(page_file))?
            }
            value => serde_json::from_value(value.clone()).context("decode inline page")?,
        };
        pages.push(render_page(page, &strings));
    }

    Ok(BundleView {
        title: localize_opt(manifest.display_name.as_deref(), &strings)
            .unwrap_or_else(|| manifest.id.clone()),
        summary: localize_opt(manifest.summary.as_deref(), &strings).unwrap_or_default(),
        pages,
    })
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> Result<T> {
    let text = fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
    serde_json::from_str(&text).with_context(|| format!("parse {}", path.display()))
}

fn load_strings(bundle_root: &Path, repo_root: &Path, locale: &str) -> Result<BTreeMap<String, String>> {
    let mut strings = BTreeMap::new();
    merge_strings(
        &mut strings,
        &repo_root
            .join("Sources")
            .join("GUIForCLICore")
            .join("Resources")
            .join("BuiltinStrings")
            .join("strings.en.toml"),
    )?;
    merge_strings(
        &mut strings,
        &bundle_root
            .join("strings")
            .join(format!("strings.{locale}.toml")),
    )?;
    if locale != "en" {
        merge_strings(&mut strings, &bundle_root.join("strings").join("strings.en.toml"))?;
    }
    Ok(strings)
}

fn merge_strings(target: &mut BTreeMap<String, String>, path: &Path) -> Result<()> {
    if !path.exists() {
        return Ok(());
    }

    let text = fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
    let value = toml::from_str::<toml::Value>(&text)
        .with_context(|| format!("parse {}", path.display()))?;
    if let Some(table) = value.as_table() {
        for (key, value) in table {
            if let Some(value) = value.as_str() {
                target.insert(key.clone(), value.to_string());
            }
        }
    }
    Ok(())
}

fn render_page(page: Page, strings: &BTreeMap<String, String>) -> PageView {
    let mut body = Vec::new();
    for section in page.sections {
        body.push(format!(
            "## {}",
            localize_opt(section.title.as_deref(), strings).unwrap_or(section.id)
        ));
        if let Some(subtitle) = localize_opt(section.subtitle.as_deref(), strings) {
            body.push(subtitle);
        }
        for control in section.controls {
            body.push(render_control(control, strings));
        }
        for action in section.actions {
            body.push(render_action(action, strings, ""));
        }
        body.push(String::new());
    }

    PageView {
        title: localize_opt(page.title.as_deref(), strings).unwrap_or(page.id),
        summary: localize_opt(page.summary.as_deref(), strings).unwrap_or_default(),
        body: body.join("\n"),
    }
}

fn render_control(control: Control, strings: &BTreeMap<String, String>) -> String {
    let label = localize_opt(control.label.as_deref(), strings).unwrap_or_else(|| control.id.clone());
    let kind = control.kind.unwrap_or_else(|| "text".to_string());
    let mut lines = vec![format!("• {label} ({kind})")];

    if let Some(value) = control.value {
        lines.push(format!("  default: {}", value_to_string(&value)));
    }
    if !control.options.is_empty() {
        let options = control
            .options
            .iter()
            .map(|option| {
                localize_opt(option.title.as_deref(), strings).unwrap_or_else(|| option.id.clone())
            })
            .collect::<Vec<_>>()
            .join(", ");
        lines.push(format!("  options: {options}"));
    }
    if let Some(tooltip) = localize_opt(control.tooltip.as_deref(), strings) {
        lines.push(format!("  {tooltip}"));
    }
    for action in control.row_actions {
        lines.push(render_action(action, strings, "  row action: "));
    }

    lines.join("\n")
}

fn render_action(action: Action, strings: &BTreeMap<String, String>, prefix: &str) -> String {
    let title = localize_opt(action.title.as_deref(), strings).unwrap_or_else(|| action.id.clone());
    let mut lines = vec![format!("{prefix}▶ {title}")];
    if let Some(tooltip) = localize_opt(action.tooltip.as_deref(), strings) {
        lines.push(format!("  {tooltip}"));
    }
    if let Some(command) = action.command {
        let executable = command.executable.unwrap_or_default();
        let arguments = command.arguments.join(" ");
        let optional = command
            .optional_arguments
            .iter()
            .map(|group| format!("[{}]", group.join(" ")))
            .collect::<Vec<_>>()
            .join(" ");
        lines.push(format!("  command: {executable} {arguments} {optional}"));
    }
    lines.join("\n")
}

fn localize_opt(value: Option<&str>, strings: &BTreeMap<String, String>) -> Option<String> {
    value.map(|value| strings.get(value).cloned().unwrap_or_else(|| value.to_string()))
}

fn value_to_string(value: &Value) -> String {
    match value {
        Value::String(value) => value.clone(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        _ => value.to_string(),
    }
}

fn set_page(ui: &AppWindow, page: &PageView) {
    ui.set_page_title(SharedString::from(page.title.as_str()));
    ui.set_page_summary(SharedString::from(page.summary.as_str()));
    ui.set_page_body(SharedString::from(page.body.as_str()));
}
