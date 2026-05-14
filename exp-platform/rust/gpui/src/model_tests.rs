use crate::args::Args;
use crate::bundle::{ActionCondition, ActionView};
use crate::execution::{
    action_arguments, action_preview, action_unavailable_reason, is_action_visible,
};
use crate::localization::LayoutDirection;
use crate::model::GpuiModel;
use std::collections::BTreeMap;
use std::path::PathBuf;

#[test]
fn action_required_placeholders_disable_until_values_exist() {
    let action = test_action(vec!["--input".to_string(), "{{input_bam}}".to_string()]);
    assert!(
        action_unavailable_reason(&action, &BTreeMap::new())
            .expect("missing input should disable")
            .contains("input bam")
    );
    assert!(
        action_unavailable_reason(
            &action,
            &BTreeMap::from([("input_bam".to_string(), "reads.bam".to_string())])
        )
        .is_none()
    );
}

#[test]
fn interpolation_includes_optional_arguments_when_complete() {
    let mut action = test_action(vec!["{{input_bam}}".to_string()]);
    action.optional_arguments = vec![vec!["--reference".to_string(), "{{reference}}".to_string()]];
    let values = BTreeMap::from([
        ("input_bam".to_string(), "reads.bam".to_string()),
        ("reference".to_string(), "hg38".to_string()),
    ]);

    assert_eq!(
        action_arguments(&action, &values),
        vec![
            "reads.bam".to_string(),
            "--reference".to_string(),
            "hg38".to_string()
        ]
    );
}

#[test]
fn condition_visibility_uses_values() {
    let mut action = test_action(Vec::new());
    action.visible_when = vec![ActionCondition {
        placeholder: "status".to_string(),
        equals: Some("ready".to_string()),
        not_equals: None,
        in_values: Vec::new(),
        not_in_values: Vec::new(),
        exists: None,
        less_than: None,
        less_than_or_equal: None,
        greater_than: None,
        greater_than_or_equal: None,
    }];

    assert!(is_action_visible(
        &action,
        &BTreeMap::from([("status".to_string(), "ready".to_string())])
    ));
    assert!(!is_action_visible(
        &action,
        &BTreeMap::from([("status".to_string(), "missing".to_string())])
    ));
}

#[test]
fn disabled_condition_uses_interpolated_tooltip() {
    let mut action = test_action(Vec::new());
    action.disabled_tooltip = "Already bootstrapped: {{ref_path}}".to_string();
    action.disabled_when = vec![ActionCondition {
        placeholder: "library.isBootstrapped".to_string(),
        equals: Some("true".to_string()),
        not_equals: None,
        in_values: Vec::new(),
        not_in_values: Vec::new(),
        exists: None,
        less_than: None,
        less_than_or_equal: None,
        greater_than: None,
        greater_than_or_equal: None,
    }];
    let values = BTreeMap::from([
        ("library.isBootstrapped".to_string(), "true".to_string()),
        ("ref_path".to_string(), "hg38".to_string()),
    ]);

    assert_eq!(
        action_unavailable_reason(&action, &values).as_deref(),
        Some("Already bootstrapped: hg38")
    );
}

#[test]
fn action_preview_interpolates_bundle_and_field_values() {
    let values = BTreeMap::from([
        ("bundleRoot".to_string(), "/bundle".to_string()),
        ("bam_path".to_string(), "reads.bam".to_string()),
    ]);
    let action = ActionView {
        executable: "{{bundleRoot}}/scripts/run-wgsextract.sh".to_string(),
        arguments: vec!["extract".to_string(), "{{bam_path}}".to_string()],
        ..test_action(Vec::new())
    };

    assert_eq!(
        action_preview(&action, &values),
        "/bundle/scripts/run-wgsextract.sh extract reads.bam"
    );
}

#[test]
fn wgs_bundle_loads_localized_rtl_metadata() {
    let _guard = crate::WGS_TEST_LOCK.lock().expect("lock WGS workspace");
    let model = load_wgs_model("ar", false, false);

    assert_eq!(model.layout_direction, LayoutDirection::RightToLeft);
    assert_eq!(model.terminal_text_direction, "ltr");
    assert!(model.pages.len() >= 4);

    let extract = model
        .pages
        .iter()
        .find(|page| page.id == "extract")
        .cloned()
        .expect("extract page");
    assert_eq!(model.page_group(&extract), "تحليل");
}

#[test]
fn wgs_shared_action_behavior_disables_and_interpolates_commands() {
    let _guard = crate::WGS_TEST_LOCK.lock().expect("lock WGS workspace");
    let model = load_wgs_model("en", false, false);
    let page = model
        .pages
        .iter()
        .find(|page| page.id == "library")
        .cloned()
        .expect("library page");
    let action = page
        .actions
        .iter()
        .find(|action| action.id == "library-bootstrapped")
        .cloned()
        .expect("bootstrapped action");
    let values = BTreeMap::from([
        ("library.isBootstrapped".to_string(), "true".to_string()),
        ("ref_path".to_string(), "runtime/reference/hg38".to_string()),
        (
            "bundleRoot".to_string(),
            model.bundle_root.display().to_string(),
        ),
    ]);

    assert!(model.action_disabled_reason(&action, &values).is_some());
    assert!(
        model
            .action_preview(&action, &values)
            .contains("runtime/reference/hg38")
    );
}

#[test]
fn check_and_benchmark_summaries_include_loaded_bundle_counts() {
    let _guard = crate::WGS_TEST_LOCK.lock().expect("lock WGS workspace");
    let model = load_wgs_model("en", true, true);
    let check = model.check_summary();
    let benchmark = model.benchmark_summary();

    assert!(check.contains("Loaded "));
    assert!(check.contains(" setup steps, "));
    assert!(benchmark.starts_with("gfc-gpui benchmark "));
    assert!(benchmark.contains("pages="));
    assert!(benchmark.contains("terminal_text_direction=ltr"));
    assert!(model.benchmark_enabled());
}

fn test_action(arguments: Vec<String>) -> ActionView {
    ActionView {
        id: "run".to_string(),
        title: "Run".to_string(),
        role: "primary".to_string(),
        executable: "/usr/bin/env".to_string(),
        arguments,
        optional_arguments: Vec::new(),
        environment: BTreeMap::new(),
        working_directory: None,
        visible_when: Vec::new(),
        disabled_when: Vec::new(),
        disabled_tooltip: String::new(),
        confirmation: None,
    }
}

fn load_wgs_model(locale: &str, benchmark: bool, benchmark_full: bool) -> GpuiModel {
    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(3)
        .expect("repo root")
        .to_path_buf();
    GpuiModel::load(Args {
        bundle: repo_root.join("examples/WGSExtract"),
        repo_root,
        locale: locale.to_string(),
        check: false,
        benchmark,
        benchmark_full,
        once: false,
        benchmark_output: None,
    })
    .expect("load WGS bundle")
}
