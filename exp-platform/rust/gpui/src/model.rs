use crate::args::Args;
use crate::bundle::{ActionView, BundleView, ControlView, PageView, SetupStepView, load_bundle};
use crate::control_text::{control_options, data_source_values, setup_command_preview};
use crate::execution::{
    action_preview, action_unavailable_reason, cancel_running_process, confirmation_prompt,
    is_action_visible, prepare_action_command, prepare_setup_command, running_process_registry,
};
use crate::localization::{LayoutDirection, layout_direction_for_locale};
use crate::metadata::load_metadata;
use crate::path_picker::pick_path;
use crate::row_actions::data_source_row_actions;
use crate::state::{
    PersistedState, control_persists_field_value, initial_field_values, load_state,
    persist_field_value, persist_selected_page, save_config_value, save_state, selected_page_index,
};
use crate::terminal::{TerminalAction, TerminalStore};
use crate::workspace::prepare_bundle_workspace;
use anyhow::Result;
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Instant;

#[derive(Debug, Clone)]
pub struct CommandLaunch {
    pub terminal_id: u64,
    pub action_id: Option<String>,
    pub setup_index: Option<usize>,
    pub command: crate::execution::PreparedCommand,
}

pub struct CommandFinished {
    pub terminal_id: u64,
    pub action_id: Option<String>,
    pub setup_index: Option<usize>,
    pub output: String,
}

pub struct GpuiModel {
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
    pub font_scale: f32,
    pub labels: BTreeMap<String, String>,
    pub layout_direction: LayoutDirection,
    pub terminal_text_direction: String,
    pub page_groups: BTreeMap<String, String>,
    pub bundle_root: PathBuf,
    pub running_action_ids: BTreeSet<String>,
    pub running_setup_indexes: BTreeSet<usize>,
    pub pending_confirmation: Option<String>,
    persisted_state: PersistedState,
    pub running_processes: crate::execution::RunningProcessRegistry,
    exit_code_reference: BTreeMap<i32, crate::exit_codes::ExitCodeReferenceView>,
    pub control_count: usize,
    pub action_count: usize,
    pub data_source_count: usize,
    pub loaded_ms: f64,
    pub ready_ms: f64,
    pub(crate) benchmark: bool,
    pub(crate) benchmark_full: bool,
    pub(crate) benchmark_output: Option<PathBuf>,
}

impl GpuiModel {
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
            args.locale,
            metadata.page_groups,
            args.benchmark,
            args.benchmark_full,
            args.benchmark_output,
            started,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn from_bundle(
        bundle: BundleView,
        bundle_root: PathBuf,
        workspace_messages: Vec<String>,
        loaded_ms: f64,
        locale: String,
        page_groups: BTreeMap<String, String>,
        benchmark: bool,
        benchmark_full: bool,
        benchmark_output: Option<PathBuf>,
        started: Instant,
    ) -> Result<Self> {
        let mut terminal = TerminalStore::new();
        let mut startup_messages = workspace_messages;
        let persisted_state = match load_state(&bundle_root) {
            Ok(state) => state,
            Err(error) => {
                startup_messages.push(format!("Could not load GPUI state: {error:#}"));
                PersistedState::default()
            }
        };
        if !startup_messages.is_empty() {
            terminal.replace_main(startup_messages.join("\n"));
        }
        terminal.set_main_labels(
            label_from(&bundle.strings, "app.terminal.mainTab.title"),
            terminal.selected_output(),
        );
        let selected_page = selected_page_index(&bundle.pages, &persisted_state);
        let field_values = initial_field_values(&bundle.pages, &persisted_state);
        let layout_direction = layout_direction_for_locale(&locale, &bundle.strings);

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
            font_scale: 1.0,
            labels: bundle.strings,
            layout_direction,
            terminal_text_direction: bundle.terminal_text_direction,
            page_groups,
            bundle_root,
            running_action_ids: BTreeSet::new(),
            running_setup_indexes: BTreeSet::new(),
            pending_confirmation: None,
            persisted_state,
            running_processes: running_process_registry(),
            exit_code_reference: bundle.exit_code_reference,
            control_count: bundle.control_count,
            action_count: bundle.action_count,
            data_source_count: bundle.data_source_count,
            loaded_ms,
            ready_ms: started.elapsed().as_secs_f64() * 1000.0,
            benchmark,
            benchmark_full,
            benchmark_output,
        })
    }

    pub fn label(&self, key: &str) -> String {
        label_from(&self.labels, key)
    }

    pub fn is_rtl(&self) -> bool {
        self.layout_direction == LayoutDirection::RightToLeft
    }

    pub fn current_page(&self) -> Option<&PageView> {
        self.pages
            .get(self.selected_page)
            .or_else(|| self.pages.first())
    }

    pub fn page_group(&self, page: &PageView) -> String {
        self.page_groups.get(&page.id).cloned().unwrap_or_default()
    }

    pub fn control_value(&self, control: &ControlView) -> String {
        self.field_values
            .get(&control.id)
            .cloned()
            .unwrap_or_else(|| control.value.clone())
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
        if let Ok(row_actions) = data_source_row_actions(
            &page.controls,
            field_values,
            &mut self.data_source_cache,
            &self.bundle_root,
        ) {
            actions.extend(row_actions);
        }
        actions
    }

    pub fn control_details(&mut self, control: &ControlView) -> String {
        control_options(
            control,
            &self.field_values,
            &mut self.data_source_cache,
            &self.bundle_root,
        )
    }

    pub fn action_disabled_reason(
        &self,
        action: &ActionView,
        values: &BTreeMap<String, String>,
    ) -> Option<String> {
        if self.running_action_ids.contains(&action.id) {
            Some(self.label("app.setup.step.running"))
        } else {
            action_unavailable_reason(action, values)
        }
    }

    pub fn action_preview(&self, action: &ActionView, values: &BTreeMap<String, String>) -> String {
        action_preview(action, values)
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

    pub fn set_control_value(&mut self, id: &str, value: String) {
        self.field_values.insert(id.to_string(), value.clone());
        self.data_source_cache.clear();
        if let Some(control) = self.control_for_id(id).cloned() {
            if control_persists_field_value(&control) {
                persist_field_value(&mut self.persisted_state, id, &value);
                self.save_state_or_log(&control.label);
            }
            if let Err(error) = save_config_value(&control, &value) {
                self.terminal
                    .push_result("Config", format!("Could not save config value: {error:#}"));
            }
        }
    }

    pub fn pick_control_path(&mut self, id: &str) {
        let Some(control) = self.control_for_id(id).cloned() else {
            return;
        };
        let current_value = self.control_value(&control);
        match pick_path(
            &control.id,
            &control.label,
            &current_value,
            &self.bundle_root,
        ) {
            Ok(Some(path)) => self.set_control_value(&control.id, path),
            Ok(None) => {}
            Err(error) => self.terminal.push_result(
                self.label("app.pathPicker.error.title"),
                format!("Could not pick path: {error:#}"),
            ),
        }
    }

    pub fn start_setup(&mut self, index: usize) -> Option<CommandLaunch> {
        let Some(step) = self.setup_steps.get(index).cloned() else {
            return None;
        };
        match prepare_setup_command(&step, &self.bundle_root) {
            Ok(command) => {
                self.running_setup_indexes.insert(index);
                Some(self.start_prepared(step.label, command, None, Some(index)))
            }
            Err(error) => {
                self.terminal.push_result(
                    step.label,
                    format!("Could not prepare setup command: {error:#}"),
                );
                None
            }
        }
    }

    pub fn start_action(&mut self, action: ActionView) -> Option<CommandLaunch> {
        let Some(page) = self.current_page().cloned() else {
            return None;
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
            return None;
        }
        self.pending_confirmation = None;
        match prepare_action_command(&action, &values, &self.bundle_root)
            .map(|command| command.with_exit_code_reference(self.exit_code_reference.clone()))
        {
            Ok(command) => Some(self.start_prepared(
                action.title.clone(),
                command,
                Some(action.id.clone()),
                None,
            )),
            Err(error) => {
                self.terminal
                    .push_result(action.title, format!("Cannot run action: {error:#}"));
                None
            }
        }
    }

    pub fn cancel_or_close_terminal(&mut self, index: usize) {
        if let Some(TerminalAction::Cancel(id)) = self.terminal.tab_action(index) {
            if let Err(error) = cancel_running_process(id, &self.running_processes) {
                self.terminal.push_result(
                    self.label("app.terminal.cancelButton.title"),
                    format!("Could not cancel command: {error:#}"),
                );
            }
        }
    }

    pub fn finish_command(&mut self, finished: CommandFinished) {
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

    pub fn setup_preview(step: &SetupStepView) -> String {
        setup_command_preview(step)
    }

    fn start_prepared(
        &mut self,
        title: String,
        command: crate::execution::PreparedCommand,
        action_id: Option<String>,
        setup_index: Option<usize>,
    ) -> CommandLaunch {
        let terminal_id = self.terminal.start_running(title, command.display());
        if let Some(action_id) = &action_id {
            self.running_action_ids.insert(action_id.clone());
        }
        CommandLaunch {
            terminal_id,
            action_id,
            setup_index,
            command,
        }
    }

    fn save_state_or_log(&mut self, label: &str) {
        if let Err(error) = save_state(&self.persisted_state, &self.bundle_root) {
            self.terminal
                .push_result("State", format!("Could not save {label}: {error:#}"));
        }
    }

    fn control_for_id(&self, id: &str) -> Option<&ControlView> {
        self.pages
            .iter()
            .flat_map(|page| page.controls.iter())
            .find(|control| control.id == id)
    }

    pub(crate) fn warm_all_pages(&self) {
        for page in &self.pages {
            let mut values = self.field_values.clone();
            values.extend(data_source_values(
                &page.controls,
                &self.field_values,
                &mut BTreeMap::new(),
                &self.bundle_root,
            ));
            let _ = page
                .actions
                .iter()
                .filter(|action| is_action_visible(action, &values))
                .count();
            for control in &page.controls {
                let _ = control_options(control, &values, &mut BTreeMap::new(), &self.bundle_root);
            }
        }
    }
}

fn workspace_open_command(path: &Path) -> Command {
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
