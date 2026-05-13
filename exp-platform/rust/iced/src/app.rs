use crate::args::Args;
use crate::bundle::{ActionView, BundleView, ControlView, PageView, SetupStepView, load_bundle};
use crate::control_text::{control_options, data_source_values};
use crate::execution::{
    action_unavailable_reason, cancel_running_process, confirmation_prompt, is_action_visible,
    prepare_action_command, prepare_setup_command, run_prepared_command_tracked,
    running_process_registry,
};
use crate::messages::{CommandFinished, Message};
use crate::metadata::load_metadata;
use crate::path_picker::pick_path;
use crate::row_actions::data_source_row_actions;
use crate::state::{
    PersistedState, control_persists_field_value, initial_field_values, load_state,
    persist_field_value, persist_selected_page, save_config_value, save_state, selected_page_index,
};
use crate::terminal::{TerminalAction, TerminalStore};
use crate::view_values::{LayoutDirection, layout_direction_for_locale};
use crate::workspace::prepare_bundle_workspace;
use anyhow::Result;
use iced::{Element, Task, Theme};
use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::process::Command;
use std::time::Instant;

pub struct IcedApp {
    pub(crate) title: String,
    pub(crate) summary: String,
    pub(crate) setup_lines: Vec<String>,
    pub(crate) setup_steps: Vec<SetupStepView>,
    pub(crate) pages: Vec<PageView>,
    pub(crate) selected_page: usize,
    pub(crate) field_values: BTreeMap<String, String>,
    pub(crate) data_source_cache: RefCell<BTreeMap<String, String>>,
    pub(crate) terminal: TerminalStore,
    pub(crate) terminal_visible: bool,
    pub(crate) terminal_height: f32,
    pub(crate) sidebar_visible: bool,
    pub(crate) font_scale: f32,
    pub(crate) labels: BTreeMap<String, String>,
    pub(crate) layout_direction: LayoutDirection,
    pub(crate) terminal_text_direction: String,
    pub(crate) page_groups: BTreeMap<String, String>,
    pub(crate) bundle_root: PathBuf,
    pub(crate) running_action_ids: BTreeSet<String>,
    pub(crate) running_setup_indexes: BTreeSet<usize>,
    pub(crate) pending_confirmation: Option<String>,
    persisted_state: PersistedState,
    running_processes: crate::execution::RunningProcessRegistry,
    exit_code_reference: BTreeMap<i32, crate::exit_codes::ExitCodeReferenceView>,
    pub(crate) control_count: usize,
    pub(crate) action_count: usize,
    pub(crate) data_source_count: usize,
    pub(crate) loaded_ms: f64,
    pub(crate) ready_ms: f64,
    pub(crate) benchmark: bool,
    pub(crate) benchmark_full: bool,
    pub(crate) benchmark_output: Option<PathBuf>,
}

impl IcedApp {
    pub fn load(args: Args) -> Result<Self> {
        let started = Instant::now();
        let (bundle_root, workspace_messages) = prepare_bundle_workspace(&args.bundle)?;
        let bundle = load_bundle(&bundle_root, &args.repo_root, &args.locale)?;
        let metadata = load_metadata(&bundle_root, &args.locale)?;
        let _metadata_terminal_direction = metadata.terminal_text_direction.clone();
        let loaded_ms = started.elapsed().as_secs_f64() * 1000.0;
        let benchmark = args.benchmark;
        let benchmark_full = args.benchmark_full;
        let benchmark_output = args.benchmark_output.clone();
        Self::from_bundle(
            bundle,
            bundle_root,
            workspace_messages,
            loaded_ms,
            args.locale,
            metadata.page_groups,
            benchmark,
            benchmark_full,
            benchmark_output,
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
                startup_messages.push(format!("Could not load Iced state: {error:#}"));
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
            data_source_cache: RefCell::new(BTreeMap::new()),
            terminal,
            terminal_visible: true,
            terminal_height: 190.0,
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

    pub fn window_title(&self) -> String {
        format!("{} - Iced", self.title)
    }

    pub fn theme(&self) -> Theme {
        Theme::Light
    }

    pub fn view(&self) -> Element<'_, Message> {
        crate::ui::view(self)
    }

    pub fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::SelectPage(index) => self.select_page(index),
            Message::ToggleSidebar => self.sidebar_visible = !self.sidebar_visible,
            Message::ToggleTerminal => self.terminal_visible = !self.terminal_visible,
            Message::SetTerminalHeight(height) => self.terminal_height = height.clamp(120.0, 430.0),
            Message::SetFontScale(scale) => self.font_scale = scale.clamp(0.8, 1.6),
            Message::ControlChanged(id, value) => self.set_control_value(&id, value),
            Message::PickPath(id) => self.pick_control_path(&id),
            Message::RunSetup(index) => return self.start_setup(index),
            Message::RunAction(action) => return self.start_action(action),
            Message::TerminalSelect(index) => self.terminal.select(index),
            Message::TerminalTabAction(index) => self.handle_terminal_action(index),
            Message::OpenWorkspace => self.open_workspace(),
            Message::CommandFinished(finished) => self.finish_command(finished),
        }
        Task::none()
    }

    pub(crate) fn label(&self, key: &str) -> String {
        label_from(&self.labels, key)
    }

    pub(crate) fn is_rtl(&self) -> bool {
        self.layout_direction == LayoutDirection::RightToLeft
    }

    pub(crate) fn current_page(&self) -> Option<&PageView> {
        self.pages
            .get(self.selected_page)
            .or_else(|| self.pages.first())
    }

    pub(crate) fn page_group(&self, page: &PageView) -> String {
        self.page_groups.get(&page.id).cloned().unwrap_or_default()
    }

    pub(crate) fn control_value(&self, control: &ControlView) -> String {
        self.field_values
            .get(&control.id)
            .cloned()
            .unwrap_or_else(|| control.value.clone())
    }

    pub(crate) fn effective_field_values(&self, page: &PageView) -> BTreeMap<String, String> {
        let mut values = self.field_values.clone();
        values.extend(data_source_values(
            &page.controls,
            &self.field_values,
            &mut self.data_source_cache.borrow_mut(),
            &self.bundle_root,
        ));
        values
    }

    pub(crate) fn visible_actions(
        &self,
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
            &mut self.data_source_cache.borrow_mut(),
            &self.bundle_root,
        ) {
            actions.extend(row_actions);
        }
        actions
    }

    pub(crate) fn control_details(&self, control: &ControlView) -> String {
        control_options(
            control,
            &self.field_values,
            &mut self.data_source_cache.borrow_mut(),
            &self.bundle_root,
        )
    }

    pub(crate) fn action_is_running(&self, action: &ActionView) -> bool {
        self.running_action_ids.contains(&action.id)
    }

    pub(crate) fn action_disabled_reason(
        &self,
        action: &ActionView,
        values: &BTreeMap<String, String>,
    ) -> Option<String> {
        if self.action_is_running(action) {
            Some(self.label("app.setup.step.running"))
        } else {
            action_unavailable_reason(action, values)
        }
    }

    fn select_page(&mut self, index: usize) {
        if index >= self.pages.len() {
            return;
        }
        self.selected_page = index;
        if let Some(page) = self.pages.get(index) {
            persist_selected_page(&mut self.persisted_state, page);
            self.save_state_or_log("selected page");
        }
    }

    fn set_control_value(&mut self, id: &str, value: String) {
        self.field_values.insert(id.to_string(), value.clone());
        self.data_source_cache.borrow_mut().clear();
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

    fn pick_control_path(&mut self, id: &str) {
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

    fn start_setup(&mut self, index: usize) -> Task<Message> {
        let Some(step) = self.setup_steps.get(index).cloned() else {
            return Task::none();
        };
        match prepare_setup_command(&step, &self.bundle_root) {
            Ok(command) => {
                self.running_setup_indexes.insert(index);
                self.spawn_command(step.label, command, None, Some(index))
            }
            Err(error) => {
                self.terminal.push_result(
                    step.label,
                    format!("Could not prepare setup command: {error:#}"),
                );
                Task::none()
            }
        }
    }

    fn start_action(&mut self, action: ActionView) -> Task<Message> {
        let Some(page) = self.current_page().cloned() else {
            return Task::none();
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
            return Task::none();
        }
        self.pending_confirmation = None;
        match prepare_action_command(&action, &values, &self.bundle_root)
            .map(|command| command.with_exit_code_reference(self.exit_code_reference.clone()))
        {
            Ok(command) => {
                self.spawn_command(action.title.clone(), command, Some(action.id.clone()), None)
            }
            Err(error) => {
                self.terminal
                    .push_result(action.title, format!("Cannot run action: {error:#}"));
                Task::none()
            }
        }
    }

    fn spawn_command(
        &mut self,
        title: String,
        command: crate::execution::PreparedCommand,
        action_id: Option<String>,
        setup_index: Option<usize>,
    ) -> Task<Message> {
        let terminal_id = self.terminal.start_running(title, command.display());
        if let Some(action_id) = &action_id {
            self.running_action_ids.insert(action_id.clone());
        }
        let registry = self.running_processes.clone();
        Task::perform(
            async move {
                let output = run_prepared_command_tracked(command, terminal_id, registry);
                CommandFinished {
                    terminal_id,
                    action_id,
                    setup_index,
                    output,
                }
            },
            Message::CommandFinished,
        )
    }

    fn handle_terminal_action(&mut self, index: usize) {
        if let Some(TerminalAction::Cancel(id)) = self.terminal.tab_action(index) {
            if let Err(error) = cancel_running_process(id, &self.running_processes) {
                self.terminal.push_result(
                    self.label("app.terminal.cancelButton.title"),
                    format!("Could not cancel command: {error:#}"),
                );
            }
        }
    }

    fn finish_command(&mut self, finished: CommandFinished) {
        self.terminal
            .finish_result(finished.terminal_id, finished.output);
        if let Some(action_id) = finished.action_id {
            self.running_action_ids.remove(&action_id);
        }
        if let Some(setup_index) = finished.setup_index {
            self.running_setup_indexes.remove(&setup_index);
        }
        self.data_source_cache.borrow_mut().clear();
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

    fn open_workspace(&mut self) {
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
mod tests {
    use super::*;
    use crate::terminal::TerminalStatus;

    #[test]
    fn terminal_status_tracks_running_commands() {
        let mut terminal = TerminalStore::new();
        let id = terminal.start_running("Example", "echo ok");
        assert_eq!(terminal.entries()[1].status, TerminalStatus::Running);
        terminal.finish_result(id, "$ echo ok\nok\n[Example exit 0]");
        assert_eq!(terminal.entries()[1].status, TerminalStatus::Ok);
    }
}
