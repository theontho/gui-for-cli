use crate::bundle::ControlView;
use crate::row_actions::{DataSourceRowView, data_source_rows};
use anyhow::Result;
use std::collections::BTreeMap;
use std::path::Path;

pub enum ControlDataRows {
    Rows(Vec<DataSourceRowView>),
    Empty,
    Error(String),
}

pub fn control_data_rows(
    control: &ControlView,
    field_values: &BTreeMap<String, String>,
    data_source_cache: &mut BTreeMap<String, String>,
    bundle_root: &Path,
) -> ControlDataRows {
    match load_rows(control, field_values, data_source_cache, bundle_root) {
        Ok(rows) if rows.is_empty() => ControlDataRows::Empty,
        Ok(rows) => ControlDataRows::Rows(rows),
        Err(error) => ControlDataRows::Error(format!("{error:#}")),
    }
}

fn load_rows(
    control: &ControlView,
    field_values: &BTreeMap<String, String>,
    data_source_cache: &mut BTreeMap<String, String>,
    bundle_root: &Path,
) -> Result<Vec<DataSourceRowView>> {
    data_source_rows(control, field_values, data_source_cache, bundle_root)
}
