use crate::bundle::ActionView;
use crate::execution::{action_preview, action_unavailable_reason};
use crate::terminal::TerminalStatus;
use eframe::egui;
use std::collections::BTreeMap;

pub fn heading(ui: &mut egui::Ui, text: &str) {
    ui.add_space(4.0);
    ui.heading(text);
    ui.separator();
}

pub fn helper_label(ui: &mut egui::Ui, helper: &str) {
    if !helper.is_empty() {
        ui.label(egui::RichText::new(helper).weak());
    }
}

pub fn status_color(status: TerminalStatus) -> egui::Color32 {
    match status {
        TerminalStatus::Ready => egui::Color32::from_rgb(96, 108, 122),
        TerminalStatus::Running => egui::Color32::from_rgb(40, 92, 210),
        TerminalStatus::Ok => egui::Color32::from_rgb(26, 128, 56),
        TerminalStatus::Warning => egui::Color32::from_rgb(191, 117, 20),
        TerminalStatus::Failed => egui::Color32::from_rgb(191, 26, 26),
    }
}

pub fn status_icon(status: TerminalStatus) -> &'static str {
    match status {
        TerminalStatus::Ready => "•",
        TerminalStatus::Running => "◐",
        TerminalStatus::Ok => "✓",
        TerminalStatus::Warning => "!",
        TerminalStatus::Failed => "×",
    }
}

pub fn action_detail(action: &ActionView, field_values: &BTreeMap<String, String>) -> String {
    if let Some(reason) = action_unavailable_reason(action, field_values) {
        format!("disabled: {reason}")
    } else {
        let role = if action.role == "primary" {
            String::new()
        } else {
            format!("{} ", action.role)
        };
        format!("{role}{}", action_preview(action, field_values))
    }
}

pub fn status_pill(ui: &mut egui::Ui, label: &str, status: &str) {
    if status.is_empty() {
        ui.label(egui::RichText::new("-").weak());
        return;
    }
    let color = match status {
        "installed" => egui::Color32::from_rgb(24, 128, 56),
        "unindexed" | "incomplete" => egui::Color32::from_rgb(191, 117, 20),
        "missing" => egui::Color32::from_gray(120),
        _ => egui::Color32::from_rgb(80, 80, 80),
    };
    egui::Frame::NONE
        .fill(color.gamma_multiply(0.10))
        .stroke(egui::Stroke::new(1.0, color.gamma_multiply(0.45)))
        .corner_radius(egui::CornerRadius::same(9))
        .inner_margin(egui::Margin::symmetric(8, 3))
        .show(ui, |ui| {
            ui.label(egui::RichText::new(label).color(color));
        });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bundle::ActionView;

    #[test]
    fn action_detail_includes_destructive_role() {
        let action = ActionView {
            id: "delete".to_string(),
            title: "Delete".to_string(),
            role: "destructive".to_string(),
            executable: "rm".to_string(),
            arguments: vec!["{{target}}".to_string()],
            optional_arguments: Vec::new(),
            environment: BTreeMap::new(),
            working_directory: None,
            visible_when: Vec::new(),
            disabled_when: Vec::new(),
            disabled_tooltip: String::new(),
            confirmation: None,
        };
        let values = BTreeMap::from([("target".to_string(), "file.bam".to_string())]);

        assert!(action_detail(&action, &values).contains("destructive rm file.bam"));
    }
}
