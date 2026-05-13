use crate::app::EguiApp;
use crate::terminal::{TerminalEntry, TerminalStatus};
use crate::ui_widgets::{status_color, status_icon};
use eframe::egui;

impl EguiApp {
    pub fn render_terminal_panel(&mut self, ctx: &egui::Context) {
        if !self.terminal_visible {
            egui::TopBottomPanel::bottom("terminal-collapsed")
                .exact_height(34.0)
                .show(ctx, |ui| {
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        if ui
                            .button(self.label("app.terminal.showOutput.label"))
                            .clicked()
                        {
                            self.terminal_visible = true;
                        }
                    });
                });
            return;
        }

        egui::TopBottomPanel::bottom("terminal")
            .resizable(true)
            .default_height(self.terminal_height)
            .height_range(120.0..=420.0)
            .show(ctx, |ui| {
                self.terminal_height = ui.available_height().max(120.0);
                self.render_terminal_header(ui);
                ui.separator();
                self.render_terminal_output(ui);
            });
    }

    fn render_terminal_header(&mut self, ui: &mut egui::Ui) {
        ui.horizontal_wrapped(|ui| {
            ui.label(egui::RichText::new(self.label("app.terminal.commandOutput.label")).strong());
            let entries = self.terminal.entries().to_vec();
            for (index, entry) in entries.iter().enumerate() {
                let selected = self
                    .terminal
                    .selected_entry()
                    .is_some_and(|selected| selected.id == entry.id);
                let title = format!(
                    "{} {} [{}]",
                    status_icon(entry.status),
                    entry.title,
                    self.localized_status_label(entry.status)
                );
                let response = ui.selectable_label(selected, title);
                if response.clicked() {
                    self.terminal.select(index);
                }
                if let Some(detail) =
                    terminal_status_detail(entry, &self.localized_status_label(entry.status))
                {
                    response.on_hover_text(detail);
                }
                if entry.closable {
                    let action = if entry.status == TerminalStatus::Running {
                        self.label("app.terminal.cancelButton.title")
                    } else {
                        self.label("app.terminal.closeButton.title")
                    };
                    if ui.small_button(action).clicked() {
                        self.handle_terminal_action(index);
                    }
                }
            }
            ui.separator();
            let autoscroll_label = self.label("app.terminal.autoscroll.label");
            ui.checkbox(&mut self.terminal_autoscroll, autoscroll_label);
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui
                    .button(self.label("app.terminal.hideOutput.label"))
                    .clicked()
                {
                    self.terminal_visible = false;
                }
            });
        });
    }

    fn render_terminal_output(&mut self, ui: &mut egui::Ui) {
        let mut output = self.terminal.selected_output();
        if self.terminal_text_direction == "rtl" {
            ui.label(
                egui::RichText::new(format!(
                    "{}: rtl",
                    self.label("app.terminal.textDirection.label")
                ))
                .weak(),
            );
        }
        egui::Frame::canvas(ui.style())
            .fill(egui::Color32::from_rgb(18, 22, 28))
            .show(ui, |ui| {
                let scroll = egui::ScrollArea::vertical().stick_to_bottom(self.terminal_autoscroll);
                scroll.show(ui, |ui| {
                    ui.add(
                        egui::TextEdit::multiline(&mut output)
                            .font(egui::TextStyle::Monospace)
                            .text_color(egui::Color32::from_rgb(230, 235, 242))
                            .desired_width(f32::INFINITY)
                            .interactive(false),
                    );
                });
            });
    }

    pub fn localized_status_label(&self, status: TerminalStatus) -> String {
        let key = match status {
            TerminalStatus::Ready => "app.setup.status.ready",
            TerminalStatus::Running => "app.setup.step.running",
            TerminalStatus::Ok => "app.setup.step.ok",
            TerminalStatus::Warning => "app.setup.step.warning",
            TerminalStatus::Failed => "app.setup.step.failed",
        };
        self.label(key)
    }
}

fn terminal_status_detail(entry: &TerminalEntry, status_label: &str) -> Option<String> {
    if matches!(
        entry.status,
        TerminalStatus::Ready | TerminalStatus::Running | TerminalStatus::Ok
    ) {
        return None;
    }
    entry
        .output
        .lines()
        .find_map(|line| line.strip_prefix("[exit explanation] "))
        .map(|detail| format!("{status_label}: {detail}"))
        .or_else(|| Some(status_label.to_string()))
}

#[allow(dead_code)]
fn status_text(status: TerminalStatus, label: &str) -> egui::RichText {
    egui::RichText::new(format!("{} {label}", status_icon(status))).color(status_color(status))
}
