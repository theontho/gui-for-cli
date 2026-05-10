use anyhow::{Context, Result, anyhow};
use serde::Deserialize;
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

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
pub struct BundleView {
    pub title: String,
    pub summary: String,
    pub pages: Vec<PageView>,
}

#[derive(Debug)]
pub struct PageView {
    pub title: String,
    pub summary: String,
    pub body: String,
}

pub fn load_bundle(bundle_root: &Path, repo_root: &Path, locale: &str) -> Result<BundleView> {
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

fn load_strings(
    bundle_root: &Path,
    repo_root: &Path,
    locale: &str,
) -> Result<BTreeMap<String, String>> {
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
        &bundle_root.join("strings").join("strings.en.toml"),
    )?;
    merge_strings(
        &mut strings,
        &bundle_root
            .join("strings")
            .join(format!("strings.{locale}.toml")),
    )?;
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
    let label =
        localize_opt(control.label.as_deref(), strings).unwrap_or_else(|| control.id.clone());
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
    value.map(|value| {
        strings
            .get(value)
            .cloned()
            .unwrap_or_else(|| value.to_string())
    })
}

fn value_to_string(value: &Value) -> String {
    match value {
        Value::String(value) => value.clone(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        _ => value.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};

    #[test]
    fn loads_wgs_extract_bundle() {
        let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .and_then(Path::parent)
            .expect("repo root")
            .to_path_buf();
        let bundle = load_bundle(
            &repo_root.join("Examples").join("WGSExtract"),
            &repo_root,
            "en",
        )
        .expect("load bundle");

        assert_eq!(bundle.title, "WGS Extract");
        assert!(bundle.pages.iter().any(|page| page.title == "FASTQ"));
        assert!(
            bundle
                .pages
                .iter()
                .any(|page| page.body.contains("command:"))
        );
    }
}
