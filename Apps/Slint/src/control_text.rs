use crate::bundle::{ControlView, DataSourceView, OptionView, SetupStepView};
use crate::execution::run_data_source;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;

pub fn control_options(
    control: &ControlView,
    field_values: &BTreeMap<String, String>,
    data_source_cache: &mut BTreeMap<String, String>,
    bundle_root: &Path,
) -> String {
    let mut lines = Vec::new();
    if !control.option_items.is_empty() {
        lines.push(format_options("options", &control.option_items));
    } else if !control.options.is_empty() {
        lines.push(format!("options: {}", control.options));
    }

    if let Some(data_source) = &control.data_source {
        lines.push(data_source_text(
            data_source,
            control,
            field_values,
            data_source_cache,
            bundle_root,
        ));
    }

    if !control.row_actions.is_empty() {
        lines.push(format!(
            "row actions: {}",
            control
                .row_actions
                .iter()
                .map(|action| action.title.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        ));
    }

    lines.join("\n")
}

pub fn setup_command_preview(step: &SetupStepView) -> String {
    let mut parts = match step.kind.as_str() {
        "pathTool" => vec!["which".to_string(), step.value.clone()],
        "setupScript" | "bundledScript" => vec!["sh".to_string(), step.value.clone()],
        "pixiInstall" => vec!["pixi".to_string(), "install".to_string()],
        "pixiRun" => vec!["pixi".to_string(), "run".to_string(), step.value.clone()],
        "homebrewPackage" => vec!["brew".to_string(), "list".to_string(), step.value.clone()],
        _ => vec![step.kind.clone(), step.value.clone()],
    };
    parts.extend(step.arguments.iter().cloned());
    if step.optional {
        parts.push("(optional)".to_string());
    }
    parts
        .into_iter()
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}

fn data_source_text(
    data_source: &DataSourceView,
    control: &ControlView,
    field_values: &BTreeMap<String, String>,
    data_source_cache: &mut BTreeMap<String, String>,
    bundle_root: &Path,
) -> String {
    let cache_key = format!("text:{}", data_source_cache_key(data_source, field_values));
    if let Some(cached) = data_source_cache.get(&cache_key) {
        return cached.clone();
    }

    let text = match run_data_source(data_source, field_values, bundle_root) {
        Ok(payload) => {
            cache_values(data_source, field_values, data_source_cache, &payload);
            data_source_payload_text(&payload, control)
        }
        Err(error) => format!("data source error: {error:#}"),
    };
    data_source_cache.insert(cache_key, text.clone());
    text
}

pub fn data_source_values(
    controls: &[ControlView],
    field_values: &BTreeMap<String, String>,
    data_source_cache: &mut BTreeMap<String, String>,
    bundle_root: &Path,
) -> BTreeMap<String, String> {
    let mut values = BTreeMap::new();
    for control in controls {
        let Some(data_source) = &control.data_source else {
            continue;
        };
        let key = format!(
            "values:{}",
            data_source_cache_key(data_source, field_values)
        );
        if let Some(cached) = data_source_cache.get(&key) {
            values.extend(decode_cached_values(cached));
            continue;
        }
        if let Ok(payload) = run_data_source(data_source, field_values, bundle_root) {
            let extracted = extract_values(&payload);
            data_source_cache.insert(key, encode_cached_values(&extracted));
            values.extend(extracted);
        }
    }
    values
}

fn data_source_cache_key(
    data_source: &DataSourceView,
    field_values: &BTreeMap<String, String>,
) -> String {
    let mut parts = vec![data_source.path.clone()];
    parts.extend(data_source.arguments.iter().cloned());
    for (key, value) in field_values {
        parts.push(format!("{key}={value}"));
    }
    parts.join("\u{1f}")
}

fn data_source_payload_text(payload: &Value, control: &ControlView) -> String {
    let mut lines = Vec::new();
    if let Some(options) = payload.get("options").and_then(Value::as_array) {
        let option_views = options
            .iter()
            .filter_map(dynamic_option_view)
            .collect::<Vec<_>>();
        if !option_views.is_empty() {
            lines.push(format_options("data source options", &option_views));
        }
    }
    if let Some(items) = payload.get("items").and_then(Value::as_array) {
        lines.push(format_items(items, control));
    }
    if let Some(values) = payload.get("values").and_then(Value::as_object) {
        let values = values
            .iter()
            .map(|(key, value)| format!("{key}={}", json_scalar(value)))
            .collect::<Vec<_>>()
            .join(", ");
        if !values.is_empty() {
            lines.push(format!("values: {values}"));
        }
    }
    if lines.is_empty() {
        "data source: no rows".to_string()
    } else {
        lines.join("\n")
    }
}

fn cache_values(
    data_source: &DataSourceView,
    field_values: &BTreeMap<String, String>,
    data_source_cache: &mut BTreeMap<String, String>,
    payload: &Value,
) {
    let key = format!(
        "values:{}",
        data_source_cache_key(data_source, field_values)
    );
    let values = extract_values(payload);
    if !values.is_empty() {
        data_source_cache.insert(key, encode_cached_values(&values));
    }
}

fn extract_values(payload: &Value) -> BTreeMap<String, String> {
    payload
        .get("values")
        .and_then(Value::as_object)
        .map(|values| {
            values
                .iter()
                .map(|(key, value)| (key.clone(), json_scalar(value)))
                .collect()
        })
        .unwrap_or_default()
}

fn encode_cached_values(values: &BTreeMap<String, String>) -> String {
    values
        .iter()
        .map(|(key, value)| format!("{}={}", key.replace('\n', " "), value.replace('\n', " ")))
        .collect::<Vec<_>>()
        .join("\n")
}

fn decode_cached_values(value: &str) -> BTreeMap<String, String> {
    value
        .lines()
        .filter_map(|line| {
            let (key, value) = line.split_once('=')?;
            Some((key.to_string(), value.to_string()))
        })
        .collect()
}

fn dynamic_option_view(value: &Value) -> Option<OptionView> {
    let id = value.get("id")?.as_str()?.to_string();
    Some(OptionView {
        title: value
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or(&id)
            .to_string(),
        group: value
            .get("group")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        selected: value
            .get("selected")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        id,
    })
}

fn format_options(label: &str, options: &[OptionView]) -> String {
    let values = options
        .iter()
        .map(|option| {
            let selected = if option.selected { " *" } else { "" };
            let group = if option.group.is_empty() {
                String::new()
            } else {
                format!(" [{}]", option.group)
            };
            format!("{}={}{}{}", option.id, option.title, group, selected)
        })
        .collect::<Vec<_>>()
        .join(", ");
    format!("{label}: {values}")
}

fn format_items(items: &[Value], control: &ControlView) -> String {
    let rows = items
        .iter()
        .take(12)
        .map(|item| format_item(item, control))
        .collect::<Vec<_>>();
    let suffix = if items.len() > rows.len() {
        format!(" (+{} more)", items.len() - rows.len())
    } else {
        String::new()
    };
    format!("items: {}{}", rows.join(" | "), suffix)
}

fn format_item(item: &Value, control: &ControlView) -> String {
    let Some(values) = item.get("values").and_then(Value::as_object) else {
        return item
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or("item")
            .to_string();
    };
    if control.columns.is_empty() {
        return values
            .iter()
            .map(|(key, value)| format!("{key}: {}", json_scalar(value)))
            .collect::<Vec<_>>()
            .join(", ");
    }
    control
        .columns
        .iter()
        .filter_map(|column| {
            values
                .get(&column.id)
                .map(|value| format!("{}: {}", column.title, json_scalar(value)))
        })
        .collect::<Vec<_>>()
        .join(", ")
}

fn json_scalar(value: &Value) -> String {
    value
        .as_str()
        .map(ToString::to_string)
        .unwrap_or_else(|| value.to_string())
}
