use crate::bundle::{ActionCondition, ActionView, load_bundle};
use crate::execution::{action_preview, action_unavailable_reason};
use crate::metadata::load_metadata;
use crate::model::XilemModel;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::Instant;

#[test]
fn loads_wgs_bundle_with_localized_groups() {
    let repo_root = repo_root();
    let bundle_root = repo_root.join("examples").join("WGSExtract");
    let bundle = load_bundle(&bundle_root, &repo_root, "en").expect("load bundle");
    let metadata = load_metadata(&bundle_root, "en").expect("load metadata");

    assert_eq!(bundle.title, "WGS Extract");
    assert!(bundle.pages.iter().any(|page| page.id == "settings"));
    assert_eq!(metadata.terminal_text_direction, "ltr");
    assert!(
        metadata
            .page_groups
            .values()
            .any(|group| group == "Convert")
    );
}

#[test]
fn localization_metadata_tracks_rtl_layout_and_terminal_direction() {
    let repo_root = repo_root();
    let bundle_root = repo_root.join("examples").join("WGSExtract");
    let bundle = load_bundle(&bundle_root, &repo_root, "ar").expect("load Arabic bundle");
    let metadata = load_metadata(&bundle_root, "ar").expect("load Arabic metadata");
    let model = XilemModel::from_bundle(
        bundle,
        test_workspace("rtl-metadata"),
        Vec::new(),
        1.0,
        metadata.page_groups.clone(),
        false,
        Instant::now(),
    )
    .expect("model");

    assert!(model.is_rtl());
    assert_eq!(model.terminal_text_direction, "ltr");
    assert!(metadata.page_groups.values().any(|group| group == "تحويل"));
}

#[test]
fn core_state_selects_page_and_updates_values() {
    let repo_root = repo_root();
    let bundle_root = repo_root.join("examples").join("WGSExtract");
    let bundle = load_bundle(&bundle_root, &repo_root, "en").expect("load bundle");
    let mut model = XilemModel::from_bundle(
        bundle,
        test_workspace("model-state"),
        Vec::new(),
        1.0,
        BTreeMap::new(),
        false,
        Instant::now(),
    )
    .expect("model");

    let settings_index = model
        .pages
        .iter()
        .position(|page| page.id == "settings")
        .expect("settings page");
    model.select_page(settings_index);
    assert_eq!(
        model.current_page().map(|page| page.id.as_str()),
        Some("settings")
    );

    let control_id = model
        .pages
        .iter()
        .flat_map(|page| page.controls.iter())
        .find(|control| control.kind == "path")
        .map(|control| control.id.clone())
        .expect("path control");
    model.set_control_value_by_id(&control_id, "/Users/example/out".to_string());
    assert_eq!(
        model.field_values.get(&control_id),
        Some(&"/Users/example/out".to_string())
    );
}

#[test]
fn required_placeholders_disable_and_interpolate_actions() {
    let mut action = ActionView {
        id: "extract".to_string(),
        title: "Extract".to_string(),
        role: "primary".to_string(),
        executable: "wgsextract".to_string(),
        arguments: vec!["--input".to_string(), "{{input_bam}}".to_string()],
        optional_arguments: vec![vec!["--reference".to_string(), "{{reference}}".to_string()]],
        environment: BTreeMap::new(),
        working_directory: None,
        visible_when: Vec::new(),
        disabled_when: Vec::new(),
        disabled_tooltip: String::new(),
        confirmation: None,
    };
    let mut values = BTreeMap::new();
    assert!(
        action_unavailable_reason(&action, &values)
            .expect("disabled")
            .contains("input bam")
    );

    values.insert("input_bam".to_string(), "sample.bam".to_string());
    action.disabled_when = vec![ActionCondition {
        placeholder: "mode".to_string(),
        equals: Some("disabled".to_string()),
        not_equals: None,
        in_values: Vec::new(),
        not_in_values: Vec::new(),
        exists: None,
        less_than: None,
        less_than_or_equal: None,
        greater_than: None,
        greater_than_or_equal: None,
    }];
    action.disabled_tooltip = "Mode {{mode}} is disabled".to_string();
    values.insert("mode".to_string(), "disabled".to_string());
    assert_eq!(
        action_unavailable_reason(&action, &values),
        Some("Mode disabled is disabled".to_string())
    );

    values.insert("mode".to_string(), "enabled".to_string());
    assert!(action_unavailable_reason(&action, &values).is_none());
    assert_eq!(
        action_preview(&action, &values),
        "wgsextract --input sample.bam"
    );

    values.insert("reference".to_string(), "GRCh38".to_string());
    assert_eq!(
        action_preview(&action, &values),
        "wgsextract --input sample.bam --reference GRCh38"
    );
}

#[test]
fn benchmark_and_check_summaries_include_bundle_counts() {
    let repo_root = repo_root();
    let bundle_root = repo_root.join("examples").join("WGSExtract");
    let bundle = load_bundle(&bundle_root, &repo_root, "en").expect("load bundle");
    let metadata = load_metadata(&bundle_root, "en").expect("load metadata");
    let mut model = XilemModel::from_bundle(
        bundle,
        test_workspace("summary"),
        Vec::new(),
        12.0,
        metadata.page_groups,
        false,
        Instant::now(),
    )
    .expect("model");

    let check = model.check_summary();
    assert!(check.contains("Loaded 9 pages"));
    assert!(check.contains("using ltr layout and ltr terminal text"));

    let benchmark = model.benchmark_summary();
    assert!(benchmark.contains("gfc-xilem-vello benchmark"));
    assert!(benchmark.contains("first_render_marker=core-ready"));
    assert!(benchmark.contains("pages=9"));
    assert!(benchmark.contains("terminal_text_direction=ltr"));
}

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .find(|candidate| candidate.join("examples").join("WGSExtract").exists())
        .expect("repo root")
        .to_path_buf()
}

fn test_workspace(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("target")
        .join("test-workspaces")
        .join(format!("{name}-{}", std::process::id()))
}
