use super::*;
use crate::bundle::{ActionView, PageView, SetupStepView};
use crate::execution::running_process_registry;
use crate::state::PersistedState;
use crate::terminal::TerminalStore;
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::sync::mpsc::channel;

#[test]
fn running_action_is_not_started_again() {
    let mut model = test_model();
    model.running_action_ids.insert("action-one".to_string());

    model.start_action(0);

    assert_eq!(model.terminal.entries().len(), 1);
}

#[test]
fn running_setup_is_not_started_again() {
    let mut model = test_model();
    model.running_setup_indexes.insert(0);

    model.start_setup(0);

    assert_eq!(model.terminal.entries().len(), 1);
}

#[test]
fn finished_command_clears_in_flight_tracking() {
    let mut model = test_model();
    let terminal_id = model.terminal.start_running("Action one", "true");
    model.running_action_ids.insert("action-one".to_string());
    model.running_setup_indexes.insert(0);
    model
        .completion_tx
        .send(CommandFinished {
            terminal_id,
            action_id: Some("action-one".to_string()),
            setup_index: Some(0),
            output: "[Action one exit 0]".to_string(),
        })
        .expect("send command completion");

    assert!(model.poll_finished_commands());

    assert!(model.running_action_ids.is_empty());
    assert!(model.running_setup_indexes.is_empty());
}

fn test_model() -> MakepadModel {
    let (completion_tx, completion_rx) = channel();
    MakepadModel {
        title: "Test".to_string(),
        summary: String::new(),
        setup_lines: Vec::new(),
        setup_steps: vec![SetupStepView {
            label: "Setup one".to_string(),
            kind: "pathTool".to_string(),
            value: "true".to_string(),
            arguments: Vec::new(),
            environment: BTreeMap::new(),
            working_directory: None,
            optional: false,
        }],
        pages: vec![PageView {
            id: "page-one".to_string(),
            title: "Page one".to_string(),
            summary: String::new(),
            body: String::new(),
            controls: Vec::new(),
            actions: vec![ActionView {
                id: "action-one".to_string(),
                title: "Action one".to_string(),
                role: "primary".to_string(),
                executable: "true".to_string(),
                arguments: Vec::new(),
                optional_arguments: Vec::new(),
                environment: BTreeMap::new(),
                working_directory: None,
                visible_when: Vec::new(),
                disabled_when: Vec::new(),
                disabled_tooltip: String::new(),
                confirmation: None,
            }],
        }],
        selected_page: 0,
        field_values: BTreeMap::new(),
        data_source_cache: BTreeMap::new(),
        terminal: TerminalStore::new(),
        terminal_visible: true,
        running_action_ids: BTreeSet::new(),
        running_setup_indexes: BTreeSet::new(),
        terminal_text_direction: "ltr".to_string(),
        interface_direction: "ltr".to_string(),
        bundle_root: PathBuf::from(env!("CARGO_MANIFEST_DIR")),
        labels: BTreeMap::new(),
        persisted_state: PersistedState::default(),
        running_processes: running_process_registry(),
        exit_code_reference: BTreeMap::new(),
        pending_confirmation: None,
        data_source_action_errors: BTreeSet::new(),
        control_count: 0,
        action_count: 1,
        data_source_count: 0,
        benchmark: false,
        benchmark_full: false,
        loaded_ms: 0.0,
        ready_ms: 0.0,
        completion_tx,
        completion_rx,
    }
}
