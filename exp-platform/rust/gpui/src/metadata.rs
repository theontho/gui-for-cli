use anyhow::{Context, Result, anyhow};
use serde::Deserialize;
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

#[derive(Debug, Default)]
pub struct GpuiMetadata {
    pub page_groups: BTreeMap<String, String>,
}

#[derive(Debug, Deserialize)]
struct ManifestMetadata {
    #[serde(default)]
    pages: Vec<Value>,
}

#[derive(Debug, Deserialize)]
struct PageMetadata {
    id: String,
    #[serde(rename = "sidebarGroup")]
    sidebar_group: Option<String>,
}

pub fn load_metadata(bundle_root: &Path, locale: &str) -> Result<GpuiMetadata> {
    let manifest: ManifestMetadata = read_json(&bundle_root.join("manifest.json"))?;
    let strings = load_bundle_strings(bundle_root, locale)?;
    let mut page_groups = BTreeMap::new();

    for page in manifest.pages {
        let page: PageMetadata = match page {
            Value::String(file_name) => {
                if file_name.contains('/') || file_name.contains('\\') || file_name.contains("..") {
                    return Err(anyhow!("invalid page file name: {file_name}"));
                }
                read_json(&bundle_root.join("pages").join(file_name))?
            }
            value => serde_json::from_value(value).context("decode inline page metadata")?,
        };
        if let Some(group) = page.sidebar_group {
            page_groups.insert(page.id, localize(&group, &strings));
        }
    }

    Ok(GpuiMetadata { page_groups })
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> Result<T> {
    let text = fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
    serde_json::from_str(&text).with_context(|| format!("parse {}", path.display()))
}

fn load_bundle_strings(bundle_root: &Path, locale: &str) -> Result<BTreeMap<String, String>> {
    let locale = locale.trim();
    let mut strings = BTreeMap::new();
    merge_strings(
        &mut strings,
        &bundle_root.join("strings").join("strings.en.toml"),
    )?;
    if locale != "en" {
        merge_strings(
            &mut strings,
            &bundle_root
                .join("strings")
                .join(locale_strings_file_name(locale)?),
        )?;
    }
    Ok(strings)
}

fn locale_strings_file_name(locale: &str) -> Result<String> {
    if locale.is_empty()
        || !locale.chars().all(|character| {
            character.is_ascii_alphanumeric() || character == '-' || character == '_'
        })
    {
        return Err(anyhow!("invalid locale code: {locale}"));
    }
    Ok(format!("strings.{locale}.toml"))
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

fn localize(value: &str, strings: &BTreeMap<String, String>) -> String {
    strings
        .get(value)
        .cloned()
        .unwrap_or_else(|| value.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn locale_file_name_rejects_path_segments() {
        assert!(locale_strings_file_name("../en").is_err());
        assert!(locale_strings_file_name("en/us").is_err());
        assert_eq!(
            locale_strings_file_name("zh-Hans").unwrap(),
            "strings.zh-Hans.toml"
        );
    }
}
