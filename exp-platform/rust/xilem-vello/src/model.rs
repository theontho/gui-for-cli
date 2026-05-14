use crate::args::Args;
use crate::bundle::{ActionView, BundleView, ControlView, PageView, SetupStepView, load_bundle};
use crate::control_text::{control_options, data_source_values};
use crate::execution::{
    action_unavailable_reason, cancel_running_process, confirmation_prompt, is_action_visible,
    prepare_action_command, prepare_setup_command, run_prepared_command_tracked,
    running_process_registry,
};
use crate::metadata::load_metadata;
use crate::path_picker::pick_path;
use crate::row_actions::data_source_row_actions;
use crate::state::{
    PersistedState, control_persists_field_value, initial_field_values, load_state,
    persist_field_value, persist_selected_page, save_config_value, save_state, selected_page_index,
};
use crate::terminal::{TerminalAction, TerminalStatus, TerminalStore};
use crate::workspace::prepare_bundle_workspace;
use anyhow::Result;
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::process::Command;
use std::sync::mpsc::{Receiver, Sender, channel};
use std::time::Instant;

pub const UI_BLOCKER: &str = "Xilem/Vello window UI is not wired yet: xilem 0.4 and Vello 0.6 APIs are still moving, so this target currently runs the shared Rust renderer core headlessly.";

pub struct XilemModel {
    pub title: String,
    pub summary: String,
    pub setup_lines: Vec<String>,
    pub setup_steps: Vec<SetupStepView>,
    pub pages: Vec<PageView>,
    pub selected_page: usize,
    pub field_values: BTreeMap<String, String>,
    pub data_source_cache: BTreeMap<String, String>,
    pub terminal: TerminalStore,
    pub terminal_visible: bool,
    pub sidebar_visible: bool,
    pub terminal_text_direction: String,
    pub interface_direction: String,
    pub bundle_root: PathBuf,
    pub page_groups: BTreeMap<String, String>,
    pub running_action_ids: BTreeSet<String>,
    pub running_setup_indexes: BTreeSet<usize>,
    pub control_count: usize,
    pub action_count: usize,
    pub data_source_count: usize,
    pub benchmark_full: bool,
    pub(crate) loaded_ms: f64,
    pub(crate) ready_ms: f64,
    labels: BTreeMap<String, String>,
    persisted_state: PersistedState,
    running_processes: crate::execution::RunningProcessRegistry,
    exit_code_reference: BTreeMap<i32, crate::exit_codes::ExitCodeReferenceView>,
    pending_confirmation: Option<String>,
    data_source_action_errors: BTreeSet<String>,
    completion_tx: Sender<CommandFinished>,
    completion_rx: Receiver<CommandFinished>,
}

pub struct CommandFinished {
    terminal_id: u64,
    action_id: Option<String>,
    setup_index: Option<usize>,
    output: String,
}

impl XilemModel {
    pub fn load(args: Args) -> Result<Self> {
        let started = Instant::now();
        let (bundle_root, workspace_messages) = prepare_bundle_workspace(&args.bundle)?;
        let bundle = load_bundle(&bundle_root, &args.repo_root, &args.locale)?;
        let metadata = load_metadata(&bundle_root, &args.locale)?;
        let loaded_ms = started.elapsed().as_secs_f64() * 1000.0;
        Self::from_bundle(
            bundle,
            bundle_root,
            workspace_messages,
            loaded_ms,
            metadata.page_groups,
            args.benchmark_full,
            started,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub(crate) fn from_bundle(
        bundle: BundleView,
        bundle_root: PathBuf,
        workspace_messages: Vec<String>,
        loaded_ms: f64,
        page_groups: BTreeMap<String, String>,
        benchmark_full: bool,
        started: Instant,
    ) -> Result<Self> {
        let mut terminal = TerminalStore::new();
        let mut startup_messages = workspace_messages;
        let persisted_state = match load_state(&bundle_root) {
            Ok(state) => state,
            Err(error) => {
                startup_messages.push(format!("Could not load Xilem/Vello state: {error:#}"));
                PersistedState::default()
            }
        };
        if !startup_messages.is_empty() {
            terminal.replace_main(startup_messages.join("\n"));
        }
        let main_output = if terminal.selected_output() == "Ready." {
            label_from(&bundle.strings, "app.setup.status.ready")
        } else {
            terminal.selected_output()
        };
        terminal.set_main_labels(
            label_from(&bundle.strings, "app.terminal.mainTab.title"),
            main_output,
        );
        let selected_page = selected_page_index(&bundle.pages, &persisted_state);
        let field_values = initial_field_values(&bundle.pages, &persisted_state);
        let interface_direction = label_from(&bundle.strings, "language.layoutDirection");
        let (completion_tx, completion_rx) = channel();

        Ok(Self {
            title: bundle.title,
            summary: bundle.summary,
            setup_lines: bundle.setup_lines,
            setup_steps: bundle.setup_steps,
            pages: bundle.pages,
            selected_page,
            field_values,
            data_source_cache: BTreeMap::new(),
            terminal,
            terminal_visible: true,
            sidebar_visible: true,
            terminal_text_direction: bundle.terminal_text_direction,
            interface_direction,
            bundle_root,
            page_groups,
            running_action_ids: BTreeSet::new(),
            running_setup_indexes: BTreeSet::new(),
            control_count: bundle.control_count,
            action_count: bundle.action_count,
            data_source_count: bundle.data_source_count,
            benchmark_full,
            loaded_ms,
            ready_ms: started.elapsed().as_secs_f64() * 1000.0,
            labels: bundle.strings,
            persisted_state,
            running_processes: running_process_registry(),
            exit_code_reference: bundle.exit_code_reference,
            pending_confirmation: None,
            data_source_action_errors: BTreeSet::new(),
            completion_tx,
            completion_rx,
        })
    }

    pub fn title(&self) -> &str {
        &self.title
    }

    pub fn label(&self, key: &str) -> String {
        label_from(&self.labels, key)
    }

    pub fn is_rtl(&self) -> bool {
        self.interface_direction == "rtl"
    }

    pub fn current_page(&self) -> Option<&PageView> {
        self.pages
            .get(self.selected_page)
            .or_else(|| self.pages.first())
    }

    pub fn page_group(&self, page: &PageView) -> String {
        self.page_groups.get(&page.id).cloned().unwrap_or_default()
    }

    pub fn select_page(&mut self, index: usize) {
        if index >= self.pages.len() {
            return;
        }
        self.selected_page = index;
        if let Some(page) = self.pages.get(index) {
            persist_selected_page(&mut self.persisted_state, page);
            self.save_state_or_log("selected page");
        }
    }

    pub fn control_value(&self, control: &ControlView) -> String {
        self.field_values
            .get(&control.id)
            .cloned()
            .unwrap_or_else(|| control.value.clone())
    }

    pub fn set_control_value_by_id(&mut self, control_id: &str, value: String) {
        let Some(control) = self.find_control(control_id).cloned() else {
            return;
        };
        self.set_control_value(&control, value);
    }

    pub fn toggle_control_option(&mut self, control_id: &str, option_id: &str, checked: bool) {
        let Some(control) = self.find_control(control_id).cloned() else {
            return;
        };
        let mut selected = self
            .control_value(&control)
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToString::to_string)
            .collect::<BTreeSet<_>>();
        if checked {
            selected.insert(option_id.to_string());
        } else {
            selected.remove(option_id);
        }
        self.set_control_value(&control, selected.into_iter().collect::<Vec<_>>().join(","));
    }

    pub fn pick_control_path_by_id(&mut self, control_id: &str) {
        let Some(control) = self.find_control(control_id).cloned() else {
            return;
        };
        let current = self.control_value(&control);
        match pick_path(&control.id, &control.label, &current, &self.bundle_root) {
            Ok(Some(path)) => self.set_control_value(&control, path),
            Ok(None) => {}
            Err(error) => self
                .terminal
                .push_result("Path picker", format!("Could not pick path: {error:#}")),
        }
    }

    pub fn effective_field_values(&mut self, page: &PageView) -> BTreeMap<String, String> {
        let mut values = self.field_values.clone();
        values.extend(data_source_values(
            &page.controls,
            &self.field_values,
            &mut self.data_source_cache,
            &self.bundle_root,
        ));
        values
    }

    pub fn visible_actions(
        &mut self,
        page: &PageView,
        field_values: &BTreeMap<String, String>,
    ) -> Vec<ActionView> {
        let mut actions = page
            .actions
            .iter()
            .filter(|action| is_action_visible(action, field_values))
            .cloned()
            .collect::<Vec<_>>();
        match data_source_row_actions(
            &page.controls,
            field_values,
            &mut self.data_source_cache,
            &self.bundle_root,
        ) {
            Ok(row_actions) => actions.extend(row_actions),
            Err(error) => {
                self.log_data_source_error(format!("Could not load row actions: {error:#}"))
            }
        }
        actions
    }

    pub fn control_details(&mut self, control: &ControlView) -> String {
        let values = self.field_values.clone();
        control_options(
            control,
            &values,
            &mut self.data_source_cache,
            &self.bundle_root,
        )
    }

    pub fn start_setup(&mut self, index: usize) {
        if self.running_setup_indexes.contains(&index) {
            return;
        }
        let Some(step) = self.setup_steps.get(index).cloned() else {
            return;
        };
        match prepare_setup_command(&step, &self.bundle_root) {
            Ok(command) => {
                self.running_setup_indexes.insert(index);
                self.spawn_command(
                    step.label.clone(),
                    command.with_exit_code_reference(self.exit_code_reference.clone()),
                    None,
                    Some(index),
                );
            }
            Err(error) => self.terminal.push_result(
                step.label.clone(),
                format!("Could not prepare setup step {}: {error}", step.label),
            ),
        }
    }

    pub fn start_action(&mut self, action: ActionView) {
        if self.running_action_ids.contains(&action.id) {
            return;
        }
        let Some(page) = self.current_page().cloned() else {
            return;
        };
        let values = self.effective_field_values(&page);
        let confirmation_key = format!("{}:{}", self.selected_page, action.id);
        if action.confirmation.is_some()
            && self.pending_confirmation.as_deref() != Some(confirmation_key.as_str())
        {
            self.pending_confirmation = Some(confirmation_key);
            let prompt =
                confirmation_prompt(&action, &values).unwrap_or_else(|| action.title.clone());
            self.terminal
                .push_result(format!("Confirm {}", action.title), prompt);
            return;
        }
        self.pending_confirmation = None;
        match prepare_action_command(&action, &values, &self.bundle_root) {
            Ok(command) => self.spawn_command(
                action.title.clone(),
                command.with_exit_code_reference(self.exit_code_reference.clone()),
                Some(action.id.clone()),
                None,
            ),
            Err(error) => self.terminal.push_result(
                action.title.clone(),
                format!("{} disabled: {error}", action.title),
            ),
        }
    }

    pub fn action_disabled_reason(
        &self,
        action: &ActionView,
        field_values: &BTreeMap<String, String>,
    ) -> Option<String> {
        if self.running_action_ids.contains(&action.id) {
            Some(self.label("app.setup.step.running"))
        } else {
            action_unavailable_reason(action, field_values)
        }
    }

    pub fn handle_terminal_action(&mut self, index: usize) {
        if let Some(TerminalAction::Cancel(id)) = self.terminal.tab_action(index) {
            if let Err(error) = cancel_running_process(id, &self.running_processes) {
                self.terminal.push_result(
                    self.label("app.terminal.cancelButton.title"),
                    format!("Could not cancel command: {error:#}"),
                );
            }
        }
    }

    pub fn poll_finished_commands(&mut self) {
        while let Ok(finished) = self.completion_rx.try_recv() {
            self.terminal
                .finish_result(finished.terminal_id, finished.output);
            if let Some(action_id) = finished.action_id {
                self.running_action_ids.remove(&action_id);
            }
            if let Some(setup_index) = finished.setup_index {
                self.running_setup_indexes.remove(&setup_index);
            }
            self.data_source_cache.clear();
            self.data_source_action_errors.clear();
        }
    }

    pub fn open_workspace(&mut self) {
        let mut command = workspace_open_command(&self.bundle_root);
        if let Err(error) = command.spawn() {
            self.terminal.push_result(
                self.label("app.terminal.processError.title"),
                format!(
                    "{} {}: {error:#}",
                    self.label("app.workspace.openButton.title"),
                    self.bundle_root.display()
                ),
            );
        }
    }

    pub fn cancel_all_running(&mut self) {
        let ids = self
            .terminal
            .entries()
            .iter()
            .filter(|entry| entry.status == TerminalStatus::Running)
            .map(|entry| entry.id)
            .collect::<Vec<_>>();
        for id in ids {
            let _ = cancel_running_process(id, &self.running_processes);
        }
    }

    fn set_control_value(&mut self, control: &ControlView, value: String) {
        self.field_values.insert(control.id.clone(), value.clone());
        if control_persists_field_value(control) {
            persist_field_value(&mut self.persisted_state, &control.id, &value);
        }
        if let Err(error) = save_config_value(control, &value) {
            self.terminal
                .push_result("Config", format!("Could not save config value: {error:#}"));
        }
        self.save_state_or_log(&control.label);
        self.data_source_cache.clear();
        self.data_source_action_errors.clear();
    }

    fn find_control(&self, control_id: &str) -> Option<&ControlView> {
        self.pages
            .iter()
            .flat_map(|page| page.controls.iter())
            .find(|control| control.id == control_id)
    }

    fn spawn_command(
        &mut self,
        title: String,
        command: crate::execution::PreparedCommand,
        action_id: Option<String>,
        setup_index: Option<usize>,
    ) {
        let command_text = command.display();
        let terminal_id = self.terminal.start_running(title, command_text);
        if let Some(action_id) = &action_id {
            self.running_action_ids.insert(action_id.clone());
        }
        let sender = self.completion_tx.clone();
        let registry = self.running_processes.clone();
        std::thread::spawn(move || {
            let output = run_prepared_command_tracked(command, terminal_id, registry);
            let _ = sender.send(CommandFinished {
                terminal_id,
                action_id,
                setup_index,
                output,
            });
        });
    }

    fn log_data_source_error(&mut self, message: String) {
        if self.data_source_action_errors.insert(message.clone()) {
            self.terminal
                .push_result(self.label("app.dataSource.error.title"), message);
        }
    }

    fn save_state_or_log(&mut self, label: &str) {
        if let Err(error) = save_state(&self.persisted_state, &self.bundle_root) {
            self.terminal
                .push_result("State", format!("Could not save {label}: {error:#}"));
        }
    }
}

impl Drop for XilemModel {
    fn drop(&mut self) {
        self.cancel_all_running();
    }
}

fn workspace_open_command(path: &PathBuf) -> Command {
    #[cfg(target_os = "macos")]
    {
        let mut command = Command::new("open");
        command.arg(path);
        command
    }
    #[cfg(target_os = "windows")]
    {
        let mut command = Command::new("explorer");
        command.arg(path);
        command
    }
    #[cfg(all(not(target_os = "macos"), not(target_os = "windows")))]
    {
        let mut command = Command::new("xdg-open");
        command.arg(path);
        command
    }
}

fn label_from(labels: &BTreeMap<String, String>, key: &str) -> String {
    labels.get(key).cloned().unwrap_or_else(|| key.to_string())
}
