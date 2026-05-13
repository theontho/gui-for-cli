use crate::app::EguiApp;
use crate::bundle::{ActionView, ControlView};
use crate::data_view::{ControlDataRows, control_data_rows};
use crate::execution::{action_preview, action_unavailable_reason};
use crate::row_actions::{DataSourceRowActionView, DataSourceRowView};
use crate::ui_widgets::{action_detail, heading, helper_label, status_pill};
use eframe::egui;
use std::collections::{BTreeMap, BTreeSet};

impl EguiApp {
    pub fn render_page(&mut self, ui: &mut egui::Ui) {
        ui.add_space(8.0);
        if !self.sidebar_visible && ui.button(self.label("app.sidebar.show.label")).clicked() {
            self.sidebar_visible = true;
        }
        let Some(page) = self.current_page().cloned() else {
            return;
        };
        egui::ScrollArea::vertical().show(ui, |ui| {
            ui.heading(&page.title);
            if !page.summary.is_empty() {
                ui.label(&page.summary);
            }
            ui.add_space(6.0);
            for line in page.body.lines() {
                render_body_line(ui, line);
            }
            for control in page.controls.clone() {
                self.render_control_card(ui, &control);
            }
            ui.add_space(8.0);
            heading(ui, &self.label("app.actionsColumn.title"));
            let effective_values = self.effective_field_values(&page);
            for action in self.visible_actions(&page, &effective_values) {
                self.render_action_row(ui, &action, &effective_values);
            }
        });
    }

    fn render_control_card(&mut self, ui: &mut egui::Ui, control: &ControlView) {
        egui::Frame::group(ui.style())
            .inner_margin(egui::Margin::symmetric(12, 10))
            .show(ui, |ui| {
                ui.label(egui::RichText::new(&control.label).strong());
                let mut value = self
                    .field_values
                    .get(&control.id)
                    .cloned()
                    .unwrap_or_else(|| control.value.clone());
                let mut edited_value = None;
                match control.kind.as_str() {
                    "toggle" => self.render_toggle(ui, control, &value, &mut edited_value),
                    "dropdown" if !control.option_items.is_empty() => {
                        self.render_dropdown(ui, control, &mut value, &mut edited_value)
                    }
                    "checkboxGroup" if !control.option_items.is_empty() => {
                        self.render_checkbox_group(ui, control, &value, &mut edited_value)
                    }
                    "infoGrid" | "libraryList" => self.render_data_control(ui, control),
                    _ => self.render_text_control(ui, control, &mut value, &mut edited_value),
                }
                if control.kind == "path"
                    && ui
                        .button(self.label("app.pathPicker.chooseButton.title"))
                        .clicked()
                {
                    self.pick_control_path(control);
                }
                if let Some(value) = edited_value {
                    self.set_control_value(control, value);
                }
                helper_label(ui, &control.helper);
                if !matches!(control.kind.as_str(), "infoGrid" | "libraryList") {
                    let details = self.control_details(control);
                    if !details.is_empty() {
                        ui.label(egui::RichText::new(details).weak());
                    }
                }
            });
        ui.add_space(8.0);
    }

    fn render_text_control(
        &mut self,
        ui: &mut egui::Ui,
        control: &ControlView,
        value: &mut String,
        edited_value: &mut Option<String>,
    ) {
        let mut input = egui::TextEdit::singleline(value).desired_width(f32::INFINITY);
        if !control.placeholder.is_empty() {
            input = input.hint_text(&control.placeholder);
        }
        if ui.add(input).on_hover_text(&control.helper).changed() {
            *edited_value = Some(value.clone());
        }
    }

    fn render_toggle(
        &mut self,
        ui: &mut egui::Ui,
        control: &ControlView,
        value: &str,
        edited_value: &mut Option<String>,
    ) {
        let mut checked = value == "true";
        if ui.checkbox(&mut checked, &control.label).changed() {
            *edited_value = Some(checked.to_string());
        }
    }

    fn render_dropdown(
        &mut self,
        ui: &mut egui::Ui,
        control: &ControlView,
        value: &mut String,
        edited_value: &mut Option<String>,
    ) {
        let selected_text = control
            .option_items
            .iter()
            .find(|option| option.id == *value)
            .map(|option| option.title.clone())
            .unwrap_or_else(|| control.placeholder.clone());
        egui::ComboBox::from_id_salt(&control.id)
            .selected_text(selected_text)
            .show_ui(ui, |ui| {
                for option in &control.option_items {
                    if ui
                        .selectable_value(value, option.id.clone(), &option.title)
                        .changed()
                    {
                        *edited_value = Some(value.clone());
                    }
                }
            });
    }

    fn render_checkbox_group(
        &mut self,
        ui: &mut egui::Ui,
        control: &ControlView,
        value: &str,
        edited_value: &mut Option<String>,
    ) {
        let mut selected = value
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToString::to_string)
            .collect::<BTreeSet<_>>();
        for option in &control.option_items {
            let mut checked = selected.contains(&option.id);
            if ui.checkbox(&mut checked, &option.title).changed() {
                if checked {
                    selected.insert(option.id.clone());
                } else {
                    selected.remove(&option.id);
                }
                *edited_value = Some(selected.iter().cloned().collect::<Vec<_>>().join(","));
            }
        }
    }

    fn render_data_control(&mut self, ui: &mut egui::Ui, control: &ControlView) {
        let field_values = self.field_values.clone();
        match control_data_rows(
            control,
            &field_values,
            &mut self.data_source_cache,
            &self.bundle_root,
        ) {
            ControlDataRows::Rows(rows) => self.render_data_rows(ui, control, &field_values, rows),
            ControlDataRows::Empty => {
                ui.label(egui::RichText::new(self.label("app.library.empty")).weak());
            }
            ControlDataRows::Error(error) => {
                ui.colored_label(
                    egui::Color32::from_rgb(191, 26, 26),
                    format!("{}: {error}", self.label("app.dataSource.error.title")),
                );
            }
        }
    }

    fn render_data_rows(
        &mut self,
        ui: &mut egui::Ui,
        control: &ControlView,
        field_values: &BTreeMap<String, String>,
        rows: Vec<DataSourceRowView>,
    ) {
        egui::ScrollArea::horizontal().show(ui, |ui| {
            egui::Grid::new(format!("{}-grid", control.id))
                .striped(true)
                .num_columns(control.columns.len() + 3)
                .show(ui, |ui| {
                    for column in &control.columns {
                        ui.strong(&column.title);
                    }
                    ui.strong(self.label("app.dataSource.statusColumn.title"));
                    ui.strong(self.label("app.dataSource.tagsColumn.title"));
                    ui.strong(self.label("app.actionsColumn.title"));
                    ui.end_row();
                    for row in rows {
                        self.render_data_row(ui, control, field_values, row);
                    }
                });
        });
    }

    fn render_data_row(
        &mut self,
        ui: &mut egui::Ui,
        control: &ControlView,
        field_values: &BTreeMap<String, String>,
        row: DataSourceRowView,
    ) {
        for column in &control.columns {
            let value = row
                .values
                .get(&column.id)
                .cloned()
                .unwrap_or_else(|| row.label.clone());
            ui.label(value);
        }
        let status_label = self
            .labels
            .get(&format!("library.status.{}", row.status))
            .cloned()
            .unwrap_or_else(|| row.status.clone());
        status_pill(ui, &status_label, &row.status);
        if row.tags.is_empty() {
            ui.label(egui::RichText::new("-").weak());
        } else {
            ui.label(row.tags.join(", "));
        }
        ui.horizontal_wrapped(|ui| {
            for row_action in row.actions {
                self.render_row_action_button(ui, row_action, field_values);
            }
        });
        ui.end_row();
    }

    fn render_row_action_button(
        &mut self,
        ui: &mut egui::Ui,
        row_action: DataSourceRowActionView,
        field_values: &BTreeMap<String, String>,
    ) {
        let running = self.running_action_ids.contains(&row_action.action.id);
        let unavailable = row_action
            .disabled_reason
            .or_else(|| action_unavailable_reason(&row_action.action, field_values));
        let enabled = unavailable.is_none() && !running;
        let title = if running {
            format!("⏳ {}", row_action.action.title)
        } else {
            row_action.action.title.clone()
        };
        let response = self.action_button(ui, &row_action.action, title, enabled);
        let hover = if running {
            self.label("app.setup.step.running")
        } else {
            unavailable.unwrap_or_else(|| action_preview(&row_action.action, field_values))
        };
        response.on_hover_text(hover);
    }

    fn render_action_row(
        &mut self,
        ui: &mut egui::Ui,
        action: &ActionView,
        field_values: &BTreeMap<String, String>,
    ) {
        ui.horizontal_wrapped(|ui| {
            let running = self.running_action_ids.contains(&action.id);
            let unavailable = action_unavailable_reason(action, field_values);
            let enabled = unavailable.is_none() && !running;
            let title = if running {
                format!("⏳ {}", action.title)
            } else {
                action.title.clone()
            };
            let response = self.action_button(ui, action, title, enabled);
            response.on_hover_text(if running {
                self.label("app.setup.step.running")
            } else {
                unavailable.unwrap_or_else(|| action_detail(action, field_values))
            });
            ui.label(egui::RichText::new(action_detail(action, field_values)).weak());
        });
    }

    fn action_button(
        &mut self,
        ui: &mut egui::Ui,
        action: &ActionView,
        title: String,
        enabled: bool,
    ) -> egui::Response {
        let mut button = egui::Button::new(title.clone());
        if action.role == "destructive" {
            button = egui::Button::new(egui::RichText::new(title).color(egui::Color32::RED));
        }
        let response = ui.add_enabled(enabled, button);
        if response.clicked() && enabled {
            self.start_action(action.clone());
        }
        response
    }
}

fn render_body_line(ui: &mut egui::Ui, line: &str) {
    if line.trim().is_empty() {
        ui.add_space(6.0);
    } else if let Some(title) = line.strip_prefix("## ") {
        heading(ui, title);
    } else {
        ui.label(line);
    }
}
