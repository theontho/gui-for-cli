use crate::bundle::DataSourceView;
use crate::execution::run_data_source;
use anyhow::Result;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;

pub fn cache_key(data_source: &DataSourceView, field_values: &BTreeMap<String, String>) -> String {
    let mut parts = vec![data_source.path.clone()];
    parts.extend(data_source.arguments.iter().cloned());
    for (key, value) in field_values {
        parts.push(format!("{key}={value}"));
    }
    parts.join("\u{1f}")
}

pub fn payload(
    data_source: &DataSourceView,
    field_values: &BTreeMap<String, String>,
    data_source_cache: &mut BTreeMap<String, String>,
    bundle_root: &Path,
) -> Result<Value> {
    let key = format!("payload:{}", cache_key(data_source, field_values));
    if let Some(cached) = data_source_cache.get(&key) {
        return serde_json::from_str(cached).map_err(Into::into);
    }
    let payload = run_data_source(data_source, field_values, bundle_root)?;
    if let Ok(encoded) = serde_json::to_string(&payload) {
        data_source_cache.insert(key, encoded);
    }
    Ok(payload)
}
