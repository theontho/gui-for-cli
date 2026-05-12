use crate::args::Args;
use crate::bundle::{ActionView, ControlView, PageView, SetupStepView, load_bundle};
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

pub struct ImGuiApp {
    pub(crate) title: String,
    pub(crate) summary: String,
    pub(crate) setup_lines: Vec<String>,
    pub(crate) setup_steps: Vec<SetupStepView>,
    pub(crate) pages: Vec<PageView>,
    pub(crate) selected_page: usize,
    pub(crate) field_values: BTreeMap<String, String>,
    pub(crate) persisted_state: PersistedState,
    pub(crate) data_source_cache: BTreeMap<String, String>,
    pub(crate) terminal: TerminalStore,
    pub(crate) terminal_visible: bool,
    pub(crate) pending_confirmation: Option<String>,
    pub(crate) running_processes: crate::execution::RunningProcessRegistry,
    pub(crate) exit_code_reference: BTreeMap<i32, crate::exit_codes::ExitCodeReferenceView>,
    pub(crate) labels: BTreeMap<String, String>,
    pub(crate) terminal_text_direction: String,
    pub(crate) interface_direction: String,
    pub(crate) bundle_root: PathBuf,
    pub(crate) terminal_height: f32,
    pub(crate) sidebar_visible: bool,
    pub(crate) terminal_autoscroll: bool,
    pub(crate) font_scale: f32,
    pub(crate) running_action_ids: BTreeSet<String>,
    pub(crate) running_setup_indexes: BTreeSet<usize>,
    data_source_action_errors: BTreeSet<String>,
    control_count: usize,
    action_count: usize,
    data_source_count: usize,
    benchmark: bool,
    benchmark_full: bool,
    once: bool,
    loaded_ms: f64,
    ready_ms: f64,
    pub(crate) completion_tx: Sender<CommandFinished>,
    pub(crate) completion_rx: Receiver<CommandFinished>,
}

pub(crate) struct CommandFinished {
    terminal_id: u64,
    action_id: Option<String>,
    setup_index: Option<usize>,
    output: String,
}

impl ImGuiApp {
    pub fn load(args: Args) -> Result<Self> {
        let started = Instant::now();
        let (bundle_root, workspace_messages) = prepare_bundle_workspace(&args.bundle)?;
        let bundle = load_bundle(&bundle_root, &args.repo_root, &args.locale)?;
        let loaded_ms = started.elapsed().as_secs_f64() * 1000.0;
        let mut terminal = TerminalStore::new();
        let mut startup_messages = workspace_messages;
        let persisted_state = match load_state(&bundle_root) {
            Ok(state) => state,
            Err(error) => {
                startup_messages.push(format!("Could not load ImGui state: {error:#}"));
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
            persisted_state,
            data_source_cache: BTreeMap::new(),
            terminal,
            terminal_visible: true,
            pending_confirmation: None,
            running_processes: running_process_registry(),
            exit_code_reference: bundle.exit_code_reference,
            labels: bundle.strings,
            terminal_text_direction: bundle.terminal_text_direction,
            interface_direction,
            bundle_root,
            terminal_height: 190.0,
            sidebar_visible: true,
            terminal_autoscroll: true,
            font_scale: 1.0,
            running_action_ids: BTreeSet::new(),
            running_setup_indexes: BTreeSet::new(),
            data_source_action_errors: BTreeSet::new(),
            control_count: bundle.control_count,
            action_count: bundle.action_count,
            data_source_count: bundle.data_source_count,
            benchmark: args.benchmark,
            benchmark_full: args.benchmark_full,
            once: args.once,
            loaded_ms,
            ready_ms: started.elapsed().as_secs_f64() * 1000.0,
            completion_tx,
            completion_rx,
        })
    }

    pub fn title(&self) -> &str {
        &self.title
    }

    pub fn once(&self) -> bool {
        self.once
    }

    pub(crate) fn label(&self, key: &str) -> String {
        label_from(&self.labels, key)
    }

    pub(crate) fn is_rtl(&self) -> bool {
        self.interface_direction == "rtl"
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
        let full_feature_warm = full_feature_warm_ms
            .map(|value| format!(" full_feature_warm_ms={value:.1}"))
            .unwrap_or_default();
        println!(
            "gfc-imgui benchmark bundle_loaded_ms={:.1} ui_ready_ms={:.1}{full_feature_warm} pages={} controls={} actions={} setup_steps={} data_sources={} data_sources_loaded={} terminal_text_direction={}",
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

    pub(crate) fn select_page(&mut self, index: usize) {
        if index >= self.pages.len() {
            return;
        }
        self.selected_page = index;
        if let Some(page) = self.pages.get(index) {
            persist_selected_page(&mut self.persisted_state, page);
            self.save_state_or_log("selected page");
        }
    }

    pub(crate) fn set_control_value(&mut self, control: &ControlView, value: String) {
        self.field_values.insert(control.id.clone(), value.clone());
        if control_persists_field_value(control) {
            persist_field_value(&mut self.persisted_state, &control.id, &value);
            self.save_state_or_log(&control.label);
        }
        if let Err(error) = save_config_value(control, &value) {
            self.terminal
                .push_result("Config", format!("Could not save config value: {error:#}"));
        }
        self.data_source_cache.clear();
    }

    pub(crate) fn pick_control_path(&mut self, control: &ControlView) {
        let current_value = self
            .field_values
            .get(&control.id)
            .cloned()
            .unwrap_or_else(|| control.value.clone());
        match pick_path(
            &control.id,
            &control.label,
            &current_value,
            &self.bundle_root,
        ) {
            Ok(Some(path)) => self.set_control_value(control, path),
            Ok(None) => {}
            Err(error) => self
                .terminal
                .push_result("Path picker", format!("Could not pick path: {error:#}")),
        }
    }

    pub(crate) fn start_action(&mut self, action: ActionView) {
        let Some(page) = self.current_page().cloned() else {
            return;
        };
        let effective_values = self.effective_field_values(&page);
        let confirmation_key = format!("{}:{}", self.selected_page, action.id);
        if action.confirmation.is_some()
            && self.pending_confirmation.as_deref() != Some(confirmation_key.as_str())
        {
            self.pending_confirmation = Some(confirmation_key);
            let prompt = confirmation_prompt(&action, &effective_values)
                .unwrap_or_else(|| action.title.clone());
            self.terminal
                .push_result(format!("Confirm {}", action.title), prompt);
            return;
        }
        self.pending_confirmation = None;
        match prepare_action_command(&action, &effective_values, &self.bundle_root) {
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

    pub(crate) fn start_setup(&mut self, index: usize) {
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
                )
            }
            Err(error) => self.terminal.push_result(
                step.label.clone(),
                format!("Could not prepare setup step {}: {error}", step.label),
            ),
        }
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

    pub(crate) fn poll_finished_commands(&mut self) {
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
        }
    }

    pub(crate) fn handle_terminal_action(&mut self, index: usize) {
        if let Some(TerminalAction::Cancel(id)) = self.terminal.tab_action(index) {
            if let Err(error) = cancel_running_process(id, &self.running_processes) {
                let cancel_title = self.label("app.terminal.cancelButton.title");
                self.terminal
                    .push_result(cancel_title, format!("Could not cancel command: {error:#}"));
            }
        }
    }

    pub(crate) fn effective_field_values(&mut self, page: &PageView) -> BTreeMap<String, String> {
        let mut values = self.field_values.clone();
        values.extend(data_source_values(
            &page.controls,
            &self.field_values,
            &mut self.data_source_cache,
            &self.bundle_root,
        ));
        values
    }

    pub(crate) fn visible_actions(
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
                let message = format!("Could not load row actions: {error:#}");
                if self.data_source_action_errors.insert(message.clone()) {
                    self.terminal
                        .push_result(self.label("app.dataSource.error.title"), message);
                }
            }
        }
        actions
    }

    fn warm_all_pages(&mut self) {
        for page in self.pages.clone() {
            let effective_values = self.effective_field_values(&page);
            let _ = self.visible_actions(&page, &effective_values);
            for control in &page.controls {
                let _ = control_options(
                    control,
                    &effective_values,
                    &mut self.data_source_cache,
                    &self.bundle_root,
                );
            }
        }
    }

    pub(crate) fn current_page(&self) -> Option<&PageView> {
        self.pages
            .get(self.selected_page)
            .or_else(|| self.pages.first())
    }

    fn save_state_or_log(&mut self, label: &str) {
        if let Err(error) = save_state(&self.persisted_state, &self.bundle_root) {
            self.terminal
                .push_result("State", format!("Could not save {label}: {error:#}"));
        }
    }

    pub(crate) fn open_workspace(&mut self) {
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
