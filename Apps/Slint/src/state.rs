use crate::bundle::{ControlView, PageView};
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct PersistedState {
    #[serde(default)]
    pub selected_page_id: String,
    #[serde(default)]
    pub field_values: BTreeMap<String, String>,
}

pub fn load_state() -> Result<PersistedState> {
    let path = state_path()?;
    if !path.exists() {
        return Ok(PersistedState::default());
    }
    let text = fs::read_to_string(&path).with_context(|| format!("read {}", path.display()))?;
    serde_json::from_str(&text).with_context(|| format!("parse {}", path.display()))
}

pub fn save_state(state: &PersistedState) -> Result<()> {
    let path = state_path()?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
    }
    let text = serde_json::to_string_pretty(state).context("encode Slint state")?;
    fs::write(&path, text).with_context(|| format!("write {}", path.display()))
}

pub fn initial_field_values(
    pages: &[PageView],
    persisted: &PersistedState,
) -> BTreeMap<String, String> {
    let mut values = BTreeMap::new();
    let mut config_cache = BTreeMap::new();
    for control in pages.iter().flat_map(|page| page.controls.iter()) {
        let config_value = config_value_for(control, &mut config_cache);
        let value = persisted
            .field_values
            .get(&control.id)
            .cloned()
            .or(config_value)
            .unwrap_or_else(|| control.value.clone());
        values.insert(control.id.clone(), value);
    }
    values
}

pub fn selected_page_index(pages: &[PageView], persisted: &PersistedState) -> usize {
    pages
        .iter()
        .position(|page| page.id == persisted.selected_page_id)
        .unwrap_or(0)
}

pub fn persist_field_value(state: &mut PersistedState, id: &str, value: &str) {
    state.field_values.insert(id.to_string(), value.to_string());
}

pub fn persist_selected_page(state: &mut PersistedState, page: &PageView) {
    state.selected_page_id = page.id.clone();
}

pub fn save_config_value(control: &ControlView, value: &str) -> Result<bool> {
    if control.config_file_path.is_empty() || control.config_key.is_empty() {
        return Ok(false);
    }
    let path = Path::new(&control.config_file_path);
    let mut table = if path.exists() {
        let text = fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
        toml::from_str::<toml::Value>(&text)
            .with_context(|| format!("parse {}", path.display()))?
            .as_table()
            .cloned()
            .unwrap_or_default()
    } else {
        toml::map::Map::new()
    };
    set_toml_scalar(&mut table, &control.config_key, value, &control.kind);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
    }
    let text = toml::to_string_pretty(&toml::Value::Table(table)).context("encode config TOML")?;
    fs::write(path, text).with_context(|| format!("write {}", path.display()))?;
    Ok(true)
}

fn config_value_for(
    control: &ControlView,
    cache: &mut BTreeMap<String, BTreeMap<String, String>>,
) -> Option<String> {
    if control.config_file_path.is_empty() || control.config_key.is_empty() {
        return None;
    }
    let values = if let Some(values) = cache.get(&control.config_file_path) {
        values
    } else {
        let loaded = load_toml_scalars(Path::new(&control.config_file_path)).unwrap_or_default();
        cache.insert(control.config_file_path.clone(), loaded);
        cache.get(&control.config_file_path)?
    };
    values.get(&control.config_key).cloned()
}

fn set_toml_scalar(
    table: &mut toml::map::Map<String, toml::Value>,
    key: &str,
    value: &str,
    kind: &str,
) {
    let parts = key.split('.').collect::<Vec<_>>();
    set_toml_scalar_parts(table, &parts, value, kind);
}

fn set_toml_scalar_parts(
    table: &mut toml::map::Map<String, toml::Value>,
    parts: &[&str],
    value: &str,
    kind: &str,
) {
    let Some((head, tail)) = parts.split_first() else {
        return;
    };
    if tail.is_empty() {
        table.insert((*head).to_string(), toml_scalar(value, kind));
        return;
    }
    let entry = table
        .entry((*head).to_string())
        .or_insert_with(|| toml::Value::Table(toml::map::Map::new()));
    if !entry.is_table() {
        *entry = toml::Value::Table(toml::map::Map::new());
    }
    if let Some(child) = entry.as_table_mut() {
        set_toml_scalar_parts(child, tail, value, kind);
    }
}

fn toml_scalar(value: &str, kind: &str) -> toml::Value {
    if kind == "toggle" {
        toml::Value::Boolean(value == "true")
    } else {
        toml::Value::String(value.to_string())
    }
}

fn load_toml_scalars(path: &Path) -> Result<BTreeMap<String, String>> {
    if !path.exists() {
        return Ok(BTreeMap::new());
    }
    let text = fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
    let value = toml::from_str::<toml::Value>(&text)
        .with_context(|| format!("parse {}", path.display()))?;
    let mut values = BTreeMap::new();
    collect_toml_scalars("", &value, &mut values);
    Ok(values)
}

fn collect_toml_scalars(prefix: &str, value: &toml::Value, values: &mut BTreeMap<String, String>) {
    match value {
        toml::Value::Table(table) => {
            for (key, value) in table {
                let next = if prefix.is_empty() {
                    key.clone()
                } else {
                    format!("{prefix}.{key}")
                };
                collect_toml_scalars(&next, value, values);
            }
        }
        toml::Value::String(value) => {
            values.insert(prefix.to_string(), value.clone());
        }
        toml::Value::Integer(value) => {
            values.insert(prefix.to_string(), value.to_string());
        }
        toml::Value::Float(value) => {
            values.insert(prefix.to_string(), value.to_string());
        }
        toml::Value::Boolean(value) => {
            values.insert(prefix.to_string(), value.to_string());
        }
        _ => {}
    }
}

fn state_path() -> Result<PathBuf> {
    if let Ok(path) = std::env::var("GUI_FOR_CLI_SLINT_STATE") {
        return Ok(PathBuf::from(path));
    }
    if cfg!(target_os = "macos") {
        return Ok(home_dir()?
            .join("Library")
            .join("Application Support")
            .join("gui-for-cli")
            .join("slint-state.json"));
    }
    if cfg!(windows) {
        if let Ok(appdata) = std::env::var("APPDATA") {
            return Ok(PathBuf::from(appdata)
                .join("gui-for-cli")
                .join("slint-state.json"));
        }
    }
    let config_root = std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or(home_dir()?.join(".config"));
    Ok(config_root.join("gui-for-cli").join("slint-state.json"))
}

fn home_dir() -> Result<PathBuf> {
    std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .map(PathBuf::from)
        .context("resolve home directory")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loads_flat_and_nested_toml_scalars() {
        let dir = std::env::temp_dir().join(format!(
            "gui-for-cli-slint-state-test-{}",
            std::process::id()
        ));
        fs::create_dir_all(&dir).expect("create temp dir");
        let path = dir.join("config.toml");
        fs::write(
            &path,
            r#"
output_directory = "/tmp/out"
[tools]
pixi = "/usr/local/bin/pixi"
"#,
        )
        .expect("write config");

        let values = load_toml_scalars(&path).expect("load toml");
        assert_eq!(
            values.get("output_directory"),
            Some(&"/tmp/out".to_string())
        );
        assert_eq!(
            values.get("tools.pixi"),
            Some(&"/usr/local/bin/pixi".to_string())
        );

        fs::remove_dir_all(&dir).expect("remove temp dir");
    }

    #[test]
    fn saves_config_setting_to_toml() {
        let dir = std::env::temp_dir().join(format!(
            "gui-for-cli-slint-config-test-{}",
            std::process::id()
        ));
        fs::create_dir_all(&dir).expect("create temp dir");
        let path = dir.join("config.toml");
        fs::write(&path, "existing = \"keep\"\n").expect("write config");
        let control = ControlView {
            id: "out_dir".to_string(),
            label: "Output".to_string(),
            kind: "path".to_string(),
            value: String::new(),
            placeholder: String::new(),
            helper: String::new(),
            options: String::new(),
            option_items: Vec::new(),
            data_source: None,
            columns: Vec::new(),
            row_actions: Vec::new(),
            config_file_path: path.display().to_string(),
            config_key: "paths.output_directory".to_string(),
        };

        assert!(save_config_value(&control, "/tmp/out").expect("save config"));
        let values = load_toml_scalars(&path).expect("reload config");
        assert_eq!(values.get("existing"), Some(&"keep".to_string()));
        assert_eq!(
            values.get("paths.output_directory"),
            Some(&"/tmp/out".to_string())
        );

        fs::remove_dir_all(&dir).expect("remove temp dir");
    }
}
