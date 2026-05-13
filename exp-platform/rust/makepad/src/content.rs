use crate::bundle::{ActionView, ControlView};
use crate::control_text::{control_options, setup_command_preview};
use crate::execution::{action_preview, action_unavailable_reason};
use crate::model::MakepadModel;
use crate::terminal::{TerminalEntry, TerminalStatus, status_label};
use std::collections::BTreeMap;

pub const MAX_PAGES: usize = 16;
pub const MAX_SETUP: usize = 8;
pub const MAX_CONTROLS: usize = 24;
pub const MAX_ACTIONS: usize = 24;
pub const MAX_TERMINALS: usize = 12;

#[derive(Clone, Default)]
pub struct PageSnapshot {
    pub title: String,
    pub summary: String,
    pub body: String,
    pub controls: Vec<ControlSlot>,
    pub actions: Vec<ActionSlot>,
}

#[derive(Clone, Default)]
pub struct ControlSlot {
    pub label: String,
    pub value: String,
    pub helper: String,
    pub show_picker: bool,
}

#[derive(Clone, Default)]
pub struct ActionSlot {
    pub title: String,
    pub preview: String,
    pub disabled: bool,
}

pub fn page_snapshot(model: &mut MakepadModel) -> PageSnapshot {
    let Some(page) = model.current_page().cloned() else {
        return PageSnapshot::default();
    };
    let values = model.effective_values_for_current_page();
    let controls = page
        .controls
        .iter()
        .take(MAX_CONTROLS)
        .map(|control| control_slot(control, model, &values))
        .collect();
    let actions = model
        .visible_actions_for_current_page()
        .into_iter()
        .take(MAX_ACTIONS)
        .map(|action| action_slot(&action, &values, model))
        .collect();
    PageSnapshot {
        title: page.title,
        summary: page.summary,
        body: page.body,
        controls,
        actions,
    }
}

pub fn setup_text(model: &MakepadModel) -> String {
    let mut lines = Vec::new();
    if !model.setup_lines.is_empty() {
        lines.extend(model.setup_lines.iter().cloned());
    }
    lines.push(format!(
        "{}: {} / {}: {}",
        model.label("app.layoutDirection.label"),
        model.interface_direction,
        model.label("app.terminal.textDirection.label"),
        model.terminal_text_direction
    ));
    lines.push(format!("Workspace: {}", model.bundle_root.display()));
    lines.join("\n")
}

pub fn terminal_tab_label(entry: &TerminalEntry) -> String {
    let icon = match entry.status {
        TerminalStatus::Ready => "•",
        TerminalStatus::Running => "⏳",
        TerminalStatus::Ok => "✓",
        TerminalStatus::Warning => "⚠",
        TerminalStatus::Failed => "✕",
    };
    format!("{icon} {}", entry.title)
}

pub fn terminal_output(model: &MakepadModel) -> String {
    let selected = model.terminal.selected_output();
    format!("direction: {}\n{}", model.terminal_text_direction, selected)
}

fn control_slot(
    control: &ControlView,
    model: &mut MakepadModel,
    values: &BTreeMap<String, String>,
) -> ControlSlot {
    let value = model
        .field_values
        .get(&control.id)
        .cloned()
        .unwrap_or_else(|| control.value.clone());
    let options = control_options(
        control,
        values,
        &mut model.data_source_cache,
        &model.bundle_root,
    );
    let mut helper = Vec::new();
    if !control.kind.is_empty() {
        helper.push(format!("kind: {}", control.kind));
    }
    if !control.helper.is_empty() {
        helper.push(control.helper.clone());
    }
    if !control.placeholder.is_empty() {
        helper.push(format!("placeholder: {}", control.placeholder));
    }
    if !options.is_empty() {
        helper.push(options);
    }
    ControlSlot {
        label: control.label.clone(),
        value,
        helper: helper.join("\n"),
        show_picker: matches!(control.kind.as_str(), "file" | "directory" | "path"),
    }
}

fn action_slot(
    action: &ActionView,
    values: &BTreeMap<String, String>,
    model: &MakepadModel,
) -> ActionSlot {
    let disabled_reason = action_unavailable_reason(action, values);
    let running = model.running_action_ids.contains(&action.id);
    let title = if running {
        format!("⏳ {}", action.title)
    } else if action.role == "destructive" {
        format!("⚠ {}", action.title)
    } else {
        action.title.clone()
    };
    let mut preview = vec![action_preview(action, values)];
    if let Some(reason) = &disabled_reason {
        preview.push(format!("disabled: {reason}"));
    }
    if !action.disabled_tooltip.is_empty() {
        preview.push(action.disabled_tooltip.clone());
    }
    ActionSlot {
        title,
        preview: preview.join("\n"),
        disabled: disabled_reason.is_some() || running,
    }
}

pub fn setup_button_title(model: &MakepadModel, index: usize) -> Option<(String, String, bool)> {
    let step = model.setup_steps.get(index)?;
    let running = model.running_setup_indexes.contains(&index);
    let title = if running {
        format!("⏳ {}", step.label)
    } else {
        format!(
            "{}: {}",
            model.label("app.setup.runButton.title"),
            step.label
        )
    };
    Some((title, setup_command_preview(step), running))
}

pub fn status_hint(entry: &TerminalEntry) -> String {
    format!("status: {}", status_label(entry.status))
}
