use crate::app_values::layout_direction_for_locale;
use crate::args::Args;
use crate::bundle::{ActionView, BundleView, ControlView, PageView, SetupStepView, load_bundle};
use crate::control_text::{data_source_values, setup_command_preview};
use crate::execution::{
    action_preview, action_unavailable_reason, cancel_running_process, confirmation_prompt,
    is_action_visible, prepare_action_command, prepare_setup_command, run_prepared_command_tracked,
    running_process_registry,
};
use crate::metadata::{RayguiMetadata, load_metadata};
use crate::path_picker::pick_path;
use crate::row_actions::data_source_row_actions;
use crate::state::{
    PersistedState, control_persists_field_value, initial_field_values, load_state,
    persist_field_value, persist_selected_page, save_config_value, save_state, selected_page_index,
};
use crate::terminal::{TerminalAction, TerminalStore};
use crate::workspace::prepare_bundle_workspace;
use anyhow::Result;
use raylib::prelude::*;
use std::cell::RefCell;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::process::Command;
use std::sync::mpsc::{Receiver, Sender, channel};
use std::thread;
use std::time::Instant;

pub struct AppState {
    pub title: String,
    pub summary: String,
    pub setup_lines: Vec<String>,
    pub setup_steps: Vec<SetupStepView>,
    pub pages: Vec<PageView>,
    pub bundle_root: PathBuf,
    pub locale: String,
    pub layout_direction: LayoutDirection,
    pub terminal_text_direction: TextDirection,
    pub page_groups: BTreeMap<String, String>,
    pub selected_page: usize,
    pub field_values: BTreeMap<String, String>,
    pub data_source_cache: RefCell<BTreeMap<String, String>>,
    pub terminal: TerminalStore,
    pub show_terminal: bool,
    pub terminal_height: f32,
    pub sidebar_scroll: Vector2,
    pub content_scroll: Vector2,
    pub terminal_scroll: Vector2,
    pub text_prompt: Option<TextPrompt>,
    pub loaded_ms: f64,
    pub control_count: usize,
    pub action_count: usize,
    pub data_source_count: usize,
    persisted: PersistedState,
    exit_code_reference: BTreeMap<i32, crate::exit_codes::ExitCodeReferenceView>,
    running_processes: crate::execution::RunningProcessRegistry,
    completed_tx: Sender<CompletedCommand>,
    completed_rx: Receiver<CompletedCommand>,
    pending_confirmation: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LayoutDirection {
    LeftToRight,
    RightToLeft,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TextDirection {
    LeftToRight,
    RightToLeft,
}

#[derive(Debug, Clone)]
pub struct TextPrompt {
    pub control_id: String,
    pub label: String,
    pub value: String,
}

#[derive(Debug, Clone)]
pub struct ActionSummary {
    pub title: String,
    pub preview: String,
    pub enabled: bool,
}

struct CompletedCommand {
    terminal_id: u64,
    output: String,
}

impl AppState {
    pub fn new(args: Args) -> Result<Self> {
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
            metadata,
        )
    }

    fn from_bundle(
        bundle: BundleView,
        bundle_root: PathBuf,
        workspace_messages: Vec<String>,
        loaded_ms: f64,
        locale: String,
        metadata: RayguiMetadata,
    ) -> Result<Self> {
        let persisted = match load_state(&bundle_root) {
            Ok(state) => state,
            Err(error) => {
                let mut state = PersistedState::default();
                state
                    .field_values
                    .insert("stateError".to_string(), format!("{error:#}"));
                state
            }
        };
        let selected_page = selected_page_index(&bundle.pages, &persisted);
        let mut terminal = TerminalStore::new();
        let mut startup_messages = workspace_messages;
        if let Some(error) = persisted.field_values.get("stateError") {
            startup_messages.push(format!("Could not load Raygui state: {error}"));
        }
        if !startup_messages.is_empty() {
            terminal.replace_main(startup_messages.join("\n"));
        }
        let field_values = initial_field_values(&bundle.pages, &persisted);
        let (completed_tx, completed_rx) = channel();
        let terminal_text_direction = if metadata.terminal_text_direction == "rtl" {
            TextDirection::RightToLeft
        } else {
            TextDirection::LeftToRight
        };
        Ok(Self {
            title: bundle.title,
            summary: bundle.summary,
            setup_lines: bundle.setup_lines,
            setup_steps: bundle.setup_steps,
            pages: bundle.pages,
            bundle_root,
            layout_direction: layout_direction_for_locale(&locale),
            locale,
            terminal_text_direction,
            page_groups: metadata.page_groups,
            selected_page,
            field_values,
            data_source_cache: RefCell::new(BTreeMap::new()),
            terminal,
            show_terminal: true,
            terminal_height: 190.0,
            sidebar_scroll: Vector2::zero(),
            content_scroll: Vector2::zero(),
            terminal_scroll: Vector2::zero(),
            text_prompt: None,
            loaded_ms,
            control_count: bundle.control_count,
            action_count: bundle.action_count,
            data_source_count: bundle.data_source_count,
            persisted,
            exit_code_reference: bundle.exit_code_reference,
            running_processes: running_process_registry(),
            completed_tx,
            completed_rx,
            pending_confirmation: None,
        })
    }

    pub fn poll_completed_commands(&mut self) {
        while let Ok(completed) = self.completed_rx.try_recv() {
            self.terminal
                .finish_result(completed.terminal_id, completed.output);
            self.data_source_cache.borrow_mut().clear();
            self.terminal_scroll = Vector2::new(0.0, -99_999.0);
        }
    }

    pub fn handle_keyboard(&mut self, rl: &mut RaylibHandle) {
        if rl.is_key_pressed(KeyboardKey::KEY_KP_ADD) || rl.is_key_pressed(KeyboardKey::KEY_EQUAL) {
            self.terminal_height = (self.terminal_height + 24.0).min(420.0);
        }
        if rl.is_key_pressed(KeyboardKey::KEY_KP_SUBTRACT)
            || rl.is_key_pressed(KeyboardKey::KEY_MINUS)
        {
            self.terminal_height = (self.terminal_height - 24.0).max(120.0);
        }

        if let Some(prompt) = &mut self.text_prompt {
            while let Some(character) = rl.get_char_pressed() {
                if !character.is_control() {
                    prompt.value.push(character);
                }
            }
            if rl.is_key_pressed(KeyboardKey::KEY_BACKSPACE) {
                prompt.value.pop();
            }
            if rl.is_key_pressed(KeyboardKey::KEY_ESCAPE) {
                self.text_prompt = None;
            }
            if rl.is_key_pressed(KeyboardKey::KEY_ENTER) {
                if let Some(prompt) = self.text_prompt.take() {
                    self.update_field(&prompt.control_id, prompt.value);
                }
            }
        }
    }

    pub fn current_page(&self) -> Option<PageView> {
        self.pages
            .get(self.selected_page)
            .cloned()
            .or_else(|| self.pages.first().cloned())
    }

    pub fn page_group(&self, page: &PageView) -> String {
        self.page_groups.get(&page.id).cloned().unwrap_or_default()
    }

    pub fn select_page(&mut self, index: usize) {
        let Some(page) = self.pages.get(index) else {
            return;
        };
        self.selected_page = index;
        persist_selected_page(&mut self.persisted, page);
        if let Err(error) = save_state(&self.persisted, &self.bundle_root) {
            self.terminal
                .push_result("State", format!("Could not save selected page: {error:#}"));
        }
    }

    pub fn open_text_prompt(&mut self, control: &ControlView) {
        self.text_prompt = Some(TextPrompt {
            control_id: control.id.clone(),
            label: control.label.clone(),
            value: self
                .field_values
                .get(&control.id)
                .cloned()
                .unwrap_or_else(|| control.value.clone()),
        });
    }

    pub fn pick_path_for(&mut self, control: &ControlView) {
        let current = self
            .field_values
            .get(&control.id)
            .map(String::as_str)
            .unwrap_or(control.value.as_str());
        match pick_path(&control.id, &control.label, current, &self.bundle_root) {
            Ok(Some(path)) => self.update_field(&control.id, path),
            Ok(None) => {}
            Err(error) => self
                .terminal
                .push_result("Path picker", format!("Could not pick path: {error:#}")),
        }
    }

    pub fn update_field(&mut self, id: &str, value: String) {
        self.field_values.insert(id.to_string(), value.clone());
        self.data_source_cache.borrow_mut().clear();
        if let Some(control) = self.control_for_id(id).cloned() {
            if control_persists_field_value(&control) {
                persist_field_value(&mut self.persisted, id, &value);
                if let Err(error) = save_state(&self.persisted, &self.bundle_root) {
                    self.terminal
                        .push_result("State", format!("Could not save field value: {error:#}"));
                }
            }
            if let Err(error) = save_config_value(&control, &value) {
                self.terminal
                    .push_result("Config", format!("Could not save config value: {error:#}"));
            }
        }
    }

    pub fn action_summaries(&self, page: &PageView) -> Vec<ActionSummary> {
        let mut cache = self.data_source_cache.borrow_mut();
        let values = self.effective_field_values(page, &mut cache);
        self.visible_actions(page, &values, &mut cache)
            .into_iter()
            .map(|action| {
                let reason = action_unavailable_reason(&action, &values);
                ActionSummary {
                    title: action.title.clone(),
                    preview: reason
                        .as_ref()
                        .map(|reason| format!("disabled: {reason}"))
                        .unwrap_or_else(|| action_preview(&action, &values)),
                    enabled: reason.is_none(),
                }
            })
            .collect()
    }

    pub fn setup_previews(&self) -> Vec<String> {
        self.setup_steps
            .iter()
            .map(setup_command_preview)
            .collect::<Vec<_>>()
    }

    pub fn setup_status_summary(&self) -> String {
        if self.setup_steps.is_empty() {
            return "No setup steps are defined for this bundle.".to_string();
        }
        if self
            .terminal
            .entries()
            .iter()
            .any(|entry| entry.status == crate::terminal::TerminalStatus::Running)
        {
            return "Setup or actions may be running. Review terminal tabs for status.".to_string();
        }
        "Review and run setup steps for this bundle.".to_string()
    }

    pub fn open_workspace(&mut self) {
        let result = if cfg!(target_os = "macos") {
            Command::new("/usr/bin/open").arg(&self.bundle_root).spawn()
        } else if cfg!(windows) {
            Command::new("explorer").arg(&self.bundle_root).spawn()
        } else {
            Command::new("xdg-open").arg(&self.bundle_root).spawn()
        };
        match result {
            Ok(_) => self.terminal.push_result(
                "Workspace",
                format!("Opened workspace: {}", self.bundle_root.display()),
            ),
            Err(error) => self.terminal.push_result(
                "Workspace",
                format!(
                    "Could not open workspace {}: {error}",
                    self.bundle_root.display()
                ),
            ),
        }
    }

    pub fn run_setup(&mut self, index: usize) {
        let Some(step) = self.setup_steps.get(index).cloned() else {
            return;
        };
        match prepare_setup_command(&step, &self.bundle_root) {
            Ok(command) => self.spawn_command(
                command.title.clone(),
                command.display(),
                move |registry_id, registry| {
                    run_prepared_command_tracked(command, registry_id, registry)
                },
            ),
            Err(error) => self.terminal.push_result(
                step.label,
                format!("Could not prepare setup command: {error:#}"),
            ),
        }
    }

    pub fn run_action(&mut self, page: &PageView, index: usize) {
        let mut cache = self.data_source_cache.borrow_mut();
        let values = self.effective_field_values(page, &mut cache);
        let actions = self.visible_actions(page, &values, &mut cache);
        drop(cache);
        let Some(action) = actions.get(index).cloned() else {
            return;
        };
        let action_key = format!("{}:{}", self.selected_page, action.id);
        if action.confirmation.is_some()
            && self.pending_confirmation.as_deref() != Some(&action_key)
        {
            self.pending_confirmation = Some(action_key);
            let prompt = confirmation_prompt(&action, &values)
                .unwrap_or_else(|| "Click the action again to confirm.".to_string());
            self.terminal
                .push_result(format!("Confirm {}", action.title), prompt);
            return;
        }
        self.pending_confirmation = None;
        match prepare_action_command(&action, &values, &self.bundle_root)
            .map(|command| command.with_exit_code_reference(self.exit_code_reference.clone()))
        {
            Ok(command) => self.spawn_command(
                command.title.clone(),
                command.display(),
                move |registry_id, registry| {
                    run_prepared_command_tracked(command, registry_id, registry)
                },
            ),
            Err(error) => self
                .terminal
                .push_result(action.title, format!("Cannot run action: {error:#}")),
        }
    }

    pub fn terminal_tab_action(&mut self, index: usize) {
        match self.terminal.tab_action(index) {
            Some(TerminalAction::Cancel(id)) => {
                if let Err(error) = cancel_running_process(id, &self.running_processes) {
                    self.terminal
                        .push_result("Cancel", format!("Could not cancel command: {error:#}"));
                }
            }
            Some(TerminalAction::Close) | None => {}
        }
    }

    fn spawn_command(
        &mut self,
        title: String,
        display: String,
        run: impl FnOnce(u64, crate::execution::RunningProcessRegistry) -> String + Send + 'static,
    ) {
        let terminal_id = self.terminal.start_running(title, display);
        let registry = self.running_processes.clone();
        let tx = self.completed_tx.clone();
        thread::spawn(move || {
            let output = run(terminal_id, registry);
            let _ = tx.send(CompletedCommand {
                terminal_id,
                output,
            });
        });
    }

    fn effective_field_values(
        &self,
        page: &PageView,
        cache: &mut BTreeMap<String, String>,
    ) -> BTreeMap<String, String> {
        let mut values = self.field_values.clone();
        values.extend(data_source_values(
            &page.controls,
            &self.field_values,
            cache,
            &self.bundle_root,
        ));
        values
    }

    fn visible_actions(
        &self,
        page: &PageView,
        values: &BTreeMap<String, String>,
        cache: &mut BTreeMap<String, String>,
    ) -> Vec<ActionView> {
        let mut actions = page
            .actions
            .iter()
            .filter(|action| is_action_visible(action, values))
            .cloned()
            .collect::<Vec<_>>();
        actions.extend(data_source_row_actions(
            &page.controls,
            values,
            cache,
            &self.bundle_root,
        ));
        actions
    }

    fn control_for_id(&self, id: &str) -> Option<&ControlView> {
        self.pages
            .iter()
            .flat_map(|page| page.controls.iter())
            .find(|control| control.id == id)
    }
}
