use crate::args::Args;
use crate::bundle::{ActionView, PageView, SetupStepView, load_bundle};
use crate::control_text::{control_options, data_source_values};
use crate::execution::{
    cancel_running_process, confirmation_prompt, is_action_visible, prepare_action_command,
    prepare_setup_command, run_prepared_command_tracked, running_process_registry,
};
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

pub struct MakepadModel {
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
    pub running_action_ids: BTreeSet<String>,
    pub running_setup_indexes: BTreeSet<usize>,
    pub terminal_text_direction: String,
    pub interface_direction: String,
    pub bundle_root: PathBuf,
    labels: BTreeMap<String, String>,
    persisted_state: PersistedState,
    running_processes: crate::execution::RunningProcessRegistry,
    exit_code_reference: BTreeMap<i32, crate::exit_codes::ExitCodeReferenceView>,
    pending_confirmation: Option<String>,
    data_source_action_errors: BTreeSet<String>,
    control_count: usize,
    action_count: usize,
    data_source_count: usize,
    benchmark: bool,
    benchmark_full: bool,
    loaded_ms: f64,
    ready_ms: f64,
    completion_tx: Sender<CommandFinished>,
    completion_rx: Receiver<CommandFinished>,
}

pub struct CommandFinished {
    terminal_id: u64,
    action_id: Option<String>,
    setup_index: Option<usize>,
    output: String,
}

impl MakepadModel {
    pub fn load(args: Args) -> Result<Self> {
        let started = Instant::now();
        let (bundle_root, workspace_messages) = prepare_bundle_workspace(&args.bundle)?;
        let bundle = load_bundle(&bundle_root, &args.repo_root, &args.locale)?;
        let loaded_ms = started.elapsed().as_secs_f64() * 1000.0;
        let persisted_state = load_state(&bundle_root).unwrap_or_default();
        let selected_page = selected_page_index(&bundle.pages, &persisted_state);
        let field_values = initial_field_values(&bundle.pages, &persisted_state);
        let mut terminal = TerminalStore::new();
        if !workspace_messages.is_empty() {
            terminal.replace_main(workspace_messages.join("\n"));
        }
        terminal.set_main_labels(
            label_from(&bundle.strings, "app.terminal.mainTab.title"),
            terminal.selected_output(),
        );
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
            running_action_ids: BTreeSet::new(),
            running_setup_indexes: BTreeSet::new(),
            terminal_text_direction: bundle.terminal_text_direction,
            interface_direction,
            bundle_root,
            labels: bundle.strings,
            persisted_state,
            running_processes: running_process_registry(),
            exit_code_reference: bundle.exit_code_reference,
            pending_confirmation: None,
            data_source_action_errors: BTreeSet::new(),
            control_count: bundle.control_count,
            action_count: bundle.action_count,
            data_source_count: bundle.data_source_count,
            benchmark: args.benchmark,
            benchmark_full: args.benchmark_full,
            loaded_ms,
            ready_ms: started.elapsed().as_secs_f64() * 1000.0,
            completion_tx,
            completion_rx,
        })
    }

    pub fn label(&self, key: &str) -> String {
        label_from(&self.labels, key)
    }

    pub fn current_page(&self) -> Option<&PageView> {
        self.pages
            .get(self.selected_page)
            .or_else(|| self.pages.first())
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

    pub fn update_field(&mut self, index: usize, value: String) {
        let Some(control) = self
            .current_page()
            .and_then(|page| page.controls.get(index))
            .cloned()
        else {
            return;
        };
        self.field_values.insert(control.id.clone(), value.clone());
        if control_persists_field_value(&control) {
            persist_field_value(&mut self.persisted_state, &control.id, &value);
        }
        if let Err(error) = save_config_value(&control, &value) {
            self.terminal
                .push_result("Config", format!("Could not save config value: {error:#}"));
        }
        self.save_state_or_log(&control.label);
        self.data_source_cache.clear();
        self.data_source_action_errors.clear();
    }

    pub fn pick_control_path(&mut self, index: usize) {
        let Some(control) = self
            .current_page()
            .and_then(|page| page.controls.get(index))
            .cloned()
        else {
            return;
        };
        let current = self
            .field_values
            .get(&control.id)
            .cloned()
            .unwrap_or_else(|| control.value.clone());
        match pick_path(&control.id, &control.label, &current, &self.bundle_root) {
            Ok(Some(path)) => self.update_field(index, path),
            Ok(None) => {}
            Err(error) => self
                .terminal
                .push_result("Path picker", format!("Could not pick path: {error:#}")),
        }
    }

    pub fn effective_values_for_current_page(&mut self) -> BTreeMap<String, String> {
        let Some(page) = self.current_page().cloned() else {
            return self.field_values.clone();
        };
        let mut values = self.field_values.clone();
        values.extend(data_source_values(
            &page.controls,
            &self.field_values,
            &mut self.data_source_cache,
            &self.bundle_root,
        ));
        values
    }

    pub fn visible_actions_for_current_page(&mut self) -> Vec<ActionView> {
        let Some(page) = self.current_page().cloned() else {
            return Vec::new();
        };
        let values = self.effective_values_for_current_page();
        let mut actions = page
            .actions
            .iter()
            .filter(|action| is_action_visible(action, &values))
            .cloned()
            .collect::<Vec<_>>();
        match data_source_row_actions(
            &page.controls,
            &values,
            &mut self.data_source_cache,
            &self.bundle_root,
        ) {
            Ok(row_actions) => actions.extend(row_actions),
            Err(error) => {
                let message = format!("Could not load row actions: {error:#}");
                if self.data_source_action_errors.insert(message.clone()) {
                    self.terminal
                        .push_result(self.label("app.dataSource.error.title"), message);
                }
            }
        }
        actions
    }

    pub fn start_action(&mut self, index: usize) {
        let actions = self.visible_actions_for_current_page();
        let Some(action) = actions.get(index).cloned() else {
            return;
        };
        if self.running_action_ids.contains(&action.id) {
            return;
        }
        let values = self.effective_values_for_current_page();
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
            Ok(command) => self.spawn_command(action.title.clone(), command, Some(action.id), None),
            Err(error) => self.terminal.push_result(
                action.title.clone(),
                format!("{} disabled: {error}", action.title),
            ),
        }
    }

    pub fn start_setup(&mut self, index: usize) {
        let Some(step) = self.setup_steps.get(index).cloned() else {
            return;
        };
        if self.running_setup_indexes.contains(&index) {
            return;
        }
        match prepare_setup_command(&step, &self.bundle_root) {
            Ok(command) => {
                self.running_setup_indexes.insert(index);
                self.spawn_command(step.label.clone(), command, None, Some(index));
            }
            Err(error) => self.terminal.push_result(
                step.label.clone(),
                format!("Could not prepare setup step {}: {error:#}", step.label),
            ),
        }
    }

    pub fn handle_terminal_tab(&mut self, index: usize) {
        if let Some(TerminalAction::Cancel(id)) = self.terminal.tab_action(index) {
            if let Err(error) = cancel_running_process(id, &self.running_processes) {
                self.terminal
                    .push_result("Cancel", format!("Could not cancel command: {error:#}"));
            }
        }
    }

    pub fn poll_finished_commands(&mut self) -> bool {
        let mut changed = false;
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
            changed = true;
        }
        changed
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

    pub fn open_workspace(&mut self) {
        if let Err(error) = workspace_open_command(&self.bundle_root).spawn() {
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

    pub fn print_benchmark_if_requested(&mut self) {
        if !self.benchmark {
            return;
        }
        let full_feature_warm_ms = if self.benchmark_full {
            let started = Instant::now();
            self.warm_all_pages();
            Some(started.elapsed().as_secs_f64() * 1000.0)
        } else {
            None
        };
        let warm = full_feature_warm_ms
            .map(|value| format!(" full_feature_warm_ms={value:.1}"))
            .unwrap_or_default();
        println!(
            "gfc-makepad benchmark bundle_loaded_ms={:.1} ui_ready_ms={:.1}{warm} pages={} controls={} actions={} setup_steps={} data_sources={} data_sources_loaded={} terminal_text_direction={}",
            self.loaded_ms,
            self.ready_ms,
            self.pages.len(),
            self.control_count,
            self.action_count,
            self.setup_steps.len(),
            self.data_source_count,
            self.data_source_cache.len(),
            self.terminal_text_direction
        );
    }

    fn spawn_command(
        &mut self,
        title: String,
        command: crate::execution::PreparedCommand,
        action_id: Option<String>,
        setup_index: Option<usize>,
    ) {
        let command = command.with_exit_code_reference(self.exit_code_reference.clone());
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

    fn warm_all_pages(&mut self) {
        for page in self.pages.clone() {
            let mut values = self.field_values.clone();
            values.extend(data_source_values(
                &page.controls,
                &self.field_values,
                &mut self.data_source_cache,
                &self.bundle_root,
            ));
            let _ = data_source_row_actions(
                &page.controls,
                &values,
                &mut self.data_source_cache,
                &self.bundle_root,
            );
            for control in &page.controls {
                let _ = control_options(
                    control,
                    &values,
                    &mut self.data_source_cache,
                    &self.bundle_root,
                );
            }
        }
    }

    fn save_state_or_log(&mut self, label: &str) {
        if let Err(error) = save_state(&self.persisted_state, &self.bundle_root) {
            self.terminal
                .push_result("State", format!("Could not save {label}: {error:#}"));
        }
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

#[cfg(test)]
#[path = "model_tests.rs"]
mod tests;
