use crate::app::ImGuiApp;
use crate::bundle::{ActionView, ControlView};
use crate::control_text::{control_options, setup_command_preview};
use crate::data_view::{ControlDataRows, control_data_rows};
use crate::execution::{action_preview, action_unavailable_reason};
use crate::row_actions::DataSourceRowView;
use crate::terminal::{TerminalEntry, TerminalStatus};
use crate::window::ImGuiFonts;
use imgui::{Condition, StyleColor, TableFlags, TreeNodeFlags, Ui};
use std::collections::{BTreeMap, BTreeSet};

impl ImGuiApp {
    pub fn render(&mut self, ui: &Ui, fonts: &ImGuiFonts) {
        self.poll_finished_commands();
        ui.set_window_font_scale(self.font_scale);
        let display_size = ui.io().display_size;
        ui.window("##gui-for-cli-imgui-root")
            .position([0.0, 0.0], Condition::Always)
            .size(display_size, Condition::Always)
            .title_bar(false)
            .movable(false)
            .resizable(false)
            .collapsible(false)
            .build(|| {
                let available = ui.content_region_avail();
                let height = available[1];
                let sidebar_width = if self.sidebar_visible { 270.0 } else { 0.0 };
                let gap = if self.sidebar_visible { 8.0 } else { 0.0 };
                let detail_width = (available[0] - sidebar_width - gap).max(320.0);
                if self.is_rtl() {
                    self.render_detail(ui, [detail_width, height], fonts);
                    if self.sidebar_visible {
                        ui.same_line();
                        self.render_sidebar(ui, [sidebar_width, height]);
                    }
                } else {
                    if self.sidebar_visible {
                        self.render_sidebar(ui, [sidebar_width, height]);
                        ui.same_line();
                    }
                    self.render_detail(ui, [detail_width, height], fonts);
                }
            });
    }

    fn render_sidebar(&mut self, ui: &Ui, size: [f32; 2]) {
        ui.child_window("sidebar")
            .size(size)
            .border(true)
            .build(|| {
                ui.text(self.title.as_str());
                ui.same_line();
                if ui.small_button(format!(
                    "{}##hide-sidebar",
                    self.label("app.sidebar.hide.label")
                )) {
                    self.sidebar_visible = false;
                }
                if !self.summary.is_empty() {
                    ui.text_wrapped(self.summary.as_str());
                }
                if !self.setup_lines.is_empty() {
                    ui.separator();
                    ui.text(self.label("app.setup.status.title"));
                    for line in &self.setup_lines {
                        ui.text_wrapped(line);
                    }
                }
                for (index, step) in self.setup_steps.clone().iter().enumerate() {
                    let running = self.running_setup_indexes.contains(&index);
                    let button_title = if running {
                        format!("{} {}##setup-{index}", spinner(ui), step.label)
                    } else {
                        format!(
                            "{}: {}##setup-{index}",
                            self.label("app.setup.runButton.title"),
                            step.label
                        )
                    };
                    ui.disabled(running, || {
                        if ui.small_button(button_title) {
                            self.start_setup(index);
                        }
                    });
                    if running {
                        ui.same_line();
                        ui.text_colored(
                            status_color(TerminalStatus::Running),
                            self.label("app.setup.step.running"),
                        );
                    }
                    ui.text_disabled(setup_command_preview(step));
                }
                ui.separator();
                self.render_standard_options(ui);
                ui.separator();
                let page_tabs = self
                    .pages
                    .iter()
                    .map(|page| page.title.clone())
                    .collect::<Vec<_>>();
                for (index, title) in page_tabs.iter().enumerate() {
                    if ui
                        .selectable_config(format!("{title}##page-{index}"))
                        .selected(index == self.selected_page)
                        .build()
                    {
                        self.select_page(index);
                    }
                }
            });
    }

    fn render_standard_options(&mut self, ui: &Ui) {
        if ui.collapsing_header(
            self.label("app.standardOptions.title"),
            TreeNodeFlags::DEFAULT_OPEN,
        ) {
            ui.text(format!(
                "{}: {}",
                self.label("language.setting.label"),
                self.label("language.name")
            ));
            ui.text(format!(
                "{}: {} / {}: {}",
                self.label("app.layoutDirection.label"),
                self.interface_direction,
                self.label("app.terminal.textDirection.label"),
                self.terminal_text_direction
            ));
            let mut scale = self.font_scale;
            if ui.slider(
                format!("{}##font-scale", self.label("app.fontSize.label")),
                0.8_f32,
                1.6_f32,
                &mut scale,
            ) {
                self.font_scale = scale;
            }
            if ui.small_button(format!(
                "{}##open-workspace",
                self.label("app.workspace.openButton.title")
            )) {
                self.open_workspace();
            }
            if ui.is_item_hovered() {
                ui.tooltip_text(self.bundle_root.display().to_string());
            }
        }
    }

    fn render_detail(&mut self, ui: &Ui, size: [f32; 2], fonts: &ImGuiFonts) {
        ui.child_window("detail").size(size).border(true).build(|| {
            if !self.sidebar_visible
                && ui.small_button(format!(
                    "{}##show-sidebar",
                    self.label("app.sidebar.show.label")
                ))
            {
                self.sidebar_visible = true;
            }
            let terminal_height = if self.terminal_visible {
                self.terminal_height + 48.0
            } else {
                34.0
            };
            let content_height = (ui.content_region_avail()[1] - terminal_height).max(180.0);
            ui.child_window("page-content")
                .size([ui.content_region_avail()[0], content_height])
                .border(false)
                .build(|| self.render_page_content(ui, fonts));
            ui.separator();
            self.render_terminal(ui);
        });
    }

    fn render_page_content(&mut self, ui: &Ui, fonts: &ImGuiFonts) {
        let Some(page) = self.current_page().cloned() else {
            return;
        };
        render_section_heading(ui, fonts, page.title.as_str());
        if !page.summary.is_empty() {
            ui.text_wrapped(page.summary.as_str());
        }
        if !page.body.is_empty() {
            ui.separator();
            render_body_text(ui, fonts, page.body.as_str());
        }
        ui.separator();
        for control in page.controls.clone() {
            self.render_control(ui, &control);
        }
        ui.separator();
        render_section_heading(ui, fonts, &self.label("app.actionsColumn.title"));
        let effective_values = self.effective_field_values(&page);
        let actions = self.visible_actions(&page, &effective_values);
        for action in actions {
            self.render_action(ui, &action, &effective_values);
        }
    }

    fn render_control(&mut self, ui: &Ui, control: &ControlView) {
        ui.separator();
        ui.text(control.label.as_str());
        let mut edited_value = None;
        let mut value = self
            .field_values
            .get(&control.id)
            .cloned()
            .unwrap_or_else(|| control.value.clone());
        match control.kind.as_str() {
            "toggle" => {
                let mut checked = value == "true";
                if ui.checkbox(format!("{}##{}", control.label, control.id), &mut checked) {
                    edited_value = Some(checked.to_string());
                }
                self.render_hover_help(ui, &control.helper);
            }
            "dropdown" if !control.option_items.is_empty() => {
                let ids = control
                    .option_items
                    .iter()
                    .map(|option| option.id.clone())
                    .collect::<Vec<_>>();
                let labels = control
                    .option_items
                    .iter()
                    .map(|option| option.title.clone())
                    .collect::<Vec<_>>();
                let mut current = ids.iter().position(|id| id == &value).unwrap_or(0);
                if ui.combo_simple_string(
                    format!("{}##{}", control.label, control.id),
                    &mut current,
                    &labels,
                ) {
                    edited_value = ids.get(current).cloned();
                }
                self.render_hover_help(ui, &control.helper);
            }
            "checkboxGroup" if !control.option_items.is_empty() => {
                let mut selected = value
                    .split(',')
                    .map(str::trim)
                    .filter(|value| !value.is_empty())
                    .map(ToString::to_string)
                    .collect::<BTreeSet<_>>();
                for option in &control.option_items {
                    let mut checked = selected.contains(&option.id);
                    if ui.checkbox(
                        format!("{}##{}-{}", option.title, control.id, option.id),
                        &mut checked,
                    ) {
                        if checked {
                            selected.insert(option.id.clone());
                        } else {
                            selected.remove(&option.id);
                        }
                        edited_value = Some(selected.iter().cloned().collect::<Vec<_>>().join(","));
                    }
                    self.render_hover_help(ui, &control.helper);
                }
            }
            "infoGrid" | "libraryList" => {
                self.render_data_control(ui, control);
                self.render_hover_help(ui, &control.helper);
            }
            _ => {
                let mut input =
                    ui.input_text(format!("{}##{}", control.label, control.id), &mut value);
                if !control.placeholder.is_empty() {
                    input = input.hint(control.placeholder.as_str());
                }
                if input.build() {
                    edited_value = Some(value);
                }
                self.render_hover_help(ui, &control.helper);
            }
        }
        if control.kind == "path"
            && ui.small_button(format!(
                "{}##{}",
                self.label("app.pathPicker.chooseButton.title"),
                control.id
            ))
        {
            self.pick_control_path(control);
        }
        self.render_hover_help(ui, &control.helper);
        if !control.helper.is_empty() {
            ui.text_disabled(control.helper.as_str());
        }
        if !matches!(control.kind.as_str(), "infoGrid" | "libraryList") {
            self.render_control_details(ui, control);
        }
        if let Some(value) = edited_value {
            self.set_control_value(control, value);
        }
    }

    fn render_hover_help(&self, ui: &Ui, helper: &str) {
        if !helper.is_empty() && ui.is_item_hovered() {
            ui.tooltip_text(helper);
        }
    }

    fn render_control_details(&mut self, ui: &Ui, control: &ControlView) {
        let details = control_options(
            control,
            &self.field_values,
            &mut self.data_source_cache,
            &self.bundle_root,
        );
        if !details.is_empty() {
            ui.text_wrapped(details);
        }
    }

    fn render_data_control(&mut self, ui: &Ui, control: &ControlView) {
        let field_values = self.field_values.clone();
        match control_data_rows(
            control,
            &field_values,
            &mut self.data_source_cache,
            &self.bundle_root,
        ) {
            ControlDataRows::Rows(rows) => self.render_data_rows(ui, control, &field_values, rows),
            ControlDataRows::Empty => ui.text_disabled(self.label("app.library.empty")),
            ControlDataRows::Error(error) => {
                ui.text_colored(
                    status_color(TerminalStatus::Failed),
                    format!("{}: {error}", self.label("app.dataSource.error.title")),
                );
            }
        }
    }

    fn render_data_rows(
        &mut self,
        ui: &Ui,
        control: &ControlView,
        field_values: &BTreeMap<String, String>,
        rows: Vec<DataSourceRowView>,
    ) {
        let column_count = control.columns.len() + 3;
        let table_flags =
            TableFlags::BORDERS | TableFlags::ROW_BG | TableFlags::RESIZABLE | TableFlags::SCROLL_X;
        if let Some(_table) =
            ui.begin_table_with_flags(format!("{}##table", control.id), column_count, table_flags)
        {
            for column in &control.columns {
                ui.table_setup_column(column.title.as_str());
            }
            ui.table_setup_column(self.label("app.dataSource.statusColumn.title"));
            ui.table_setup_column(self.label("app.dataSource.tagsColumn.title"));
            ui.table_setup_column(self.label("app.actionsColumn.title"));
            ui.table_headers_row();

            for row in rows {
                ui.table_next_row();
                for column in &control.columns {
                    ui.table_next_column();
                    let value = row
                        .values
                        .get(&column.id)
                        .cloned()
                        .unwrap_or_else(|| row.label.clone());
                    ui.text_wrapped(value);
                }
                ui.table_next_column();
                self.render_status_pill(ui, &row.status);
                ui.table_next_column();
                if row.tags.is_empty() {
                    ui.text_disabled("-");
                } else {
                    ui.text_colored([0.22, 0.32, 0.65, 1.0], row.tags.join(", "));
                }
                ui.table_next_column();
                for (row_action_index, row_action) in row.actions.into_iter().enumerate() {
                    let disabled = row_action.disabled_reason.clone();
                    let instance_id =
                        format!("{}-row-action-{row_action_index}", row_action.action.id);
                    self.render_row_action(
                        ui,
                        row_action.action,
                        disabled,
                        field_values,
                        &instance_id,
                    );
                    ui.same_line();
                }
            }
        }
    }

    fn render_status_pill(&self, ui: &Ui, status: &str) {
        if status.is_empty() {
            ui.text_disabled("-");
            return;
        }
        let label = self
            .labels
            .get(&format!("library.status.{status}"))
            .cloned()
            .unwrap_or_else(|| status.to_string());
        let color = match status {
            "installed" => [0.10, 0.50, 0.22, 1.0],
            "unindexed" | "incomplete" => [0.75, 0.46, 0.08, 1.0],
            "missing" => [0.55, 0.55, 0.55, 1.0],
            _ => [0.30, 0.30, 0.30, 1.0],
        };
        ui.text_colored(color, label);
    }

    fn render_row_action(
        &mut self,
        ui: &Ui,
        action: ActionView,
        disabled_reason: Option<String>,
        field_values: &BTreeMap<String, String>,
        instance_id: &str,
    ) {
        let running = self.running_action_ids.contains(&action.id);
        let unavailable =
            disabled_reason.or_else(|| action_unavailable_reason(&action, field_values));
        let enabled = unavailable.is_none() && !running;
        let title = if running {
            format!("{} {}##row-action-{instance_id}", spinner(ui), action.title)
        } else {
            format!("{}##row-action-{instance_id}", action.title)
        };
        self.render_action_button(ui, &action, title, enabled);
        if ui.is_item_hovered() {
            let detail = if running {
                self.label("app.setup.step.running")
            } else {
                unavailable.unwrap_or_else(|| action_preview(&action, field_values))
            };
            ui.tooltip_text(detail);
        }
    }

    fn render_action(
        &mut self,
        ui: &Ui,
        action: &ActionView,
        field_values: &BTreeMap<String, String>,
    ) {
        let unavailable = action_unavailable_reason(action, field_values);
        let running = self.running_action_ids.contains(&action.id);
        let enabled = unavailable.is_none() && !running;
        let title = if running {
            format!("{} {}##action-{}", spinner(ui), action.title, action.id)
        } else {
            format!("{}##action-{}", action.title, action.id)
        };
        self.render_action_button(ui, action, title, enabled);
        let label = if running {
            self.label("app.setup.step.running")
        } else {
            unavailable.unwrap_or_else(|| action_label(action, field_values))
        };
        ui.text_wrapped(label);
    }

    fn render_action_button(&mut self, ui: &Ui, action: &ActionView, title: String, enabled: bool) {
        let destructive = action.role == "destructive";
        let style_tokens = if destructive {
            vec![
                ui.push_style_color(StyleColor::Button, [0.70, 0.12, 0.12, 1.0]),
                ui.push_style_color(StyleColor::ButtonHovered, [0.86, 0.18, 0.18, 1.0]),
                ui.push_style_color(StyleColor::ButtonActive, [0.55, 0.08, 0.08, 1.0]),
            ]
        } else {
            Vec::new()
        };
        ui.disabled(!enabled, || {
            if ui.button(title) && enabled {
                self.start_action(action.clone());
            }
        });
        drop(style_tokens);
    }

    fn render_terminal(&mut self, ui: &Ui) {
        if !self.terminal_visible {
            if ui.small_button(self.label("app.terminal.showOutput.label")) {
                self.terminal_visible = true;
            }
            return;
        }
        ui.text(self.label("app.terminal.commandOutput.label"));
        ui.same_line();
        let mut terminal_height = self.terminal_height;
        let max_height = (ui.io().display_size[1] * 0.5).max(180.0);
        if ui.slider(
            "##terminal-height",
            120.0_f32,
            max_height,
            &mut terminal_height,
        ) {
            self.terminal_height = terminal_height;
        }
        ui.same_line();
        if ui.checkbox(
            format!(
                "{}##terminal-autoscroll",
                self.label("app.terminal.autoscroll.label")
            ),
            &mut self.terminal_autoscroll,
        ) && self.terminal_autoscroll
        {
            ui.set_scroll_here_y_with_ratio(1.0);
        }
        ui.child_window("terminal")
            .size([ui.content_region_avail()[0], self.terminal_height])
            .border(true)
            .build(|| {
                for (index, entry) in self.terminal.entries().to_vec().iter().enumerate() {
                    ui.text_colored(status_color(entry.status), status_icon(entry.status));
                    ui.same_line();
                    let title = format!(
                        "{} [{}]##terminal-{index}",
                        entry.title,
                        self.localized_status_label(entry.status)
                    );
                    if ui.small_button(title) {
                        self.terminal.select(index);
                    }
                    if entry.closable {
                        ui.same_line();
                        let action = if entry.status == TerminalStatus::Running {
                            self.label("app.terminal.cancelButton.title")
                        } else {
                            self.label("app.terminal.closeButton.title")
                        };
                        if ui.small_button(format!("{action}##terminal-action-{index}")) {
                            self.handle_terminal_action(index);
                        }
                    }
                    ui.same_line();
                }
                let hide_label = self.label("app.terminal.hideOutput.label");
                let button_width = ui.calc_text_size(&hide_label)[0] + 20.0;
                let available_width = ui.content_region_avail()[0];
                if available_width > button_width {
                    ui.same_line_with_pos((available_width - button_width).max(0.0));
                }
                if ui.small_button(hide_label) {
                    self.terminal_visible = false;
                }
                if ui.is_item_hovered() {
                    ui.tooltip_text(self.label("app.terminal.hideOutput.label"));
                }
                if let Some(entry) = self.terminal.selected_entry() {
                    if let Some(detail) =
                        terminal_status_detail(entry, &self.localized_status_label(entry.status))
                    {
                        ui.text_wrapped(detail);
                    }
                }
                ui.separator();
                self.render_terminal_output(ui);
            });
    }

    fn render_terminal_output(&mut self, ui: &Ui) {
        let output = self.terminal.selected_output();
        ui.child_window("terminal-output")
            .size([
                ui.content_region_avail()[0],
                ui.content_region_avail()[1].max(80.0),
            ])
            .border(false)
            .build(|| {
                if self.terminal_text_direction == "rtl" {
                    ui.text_disabled(format!(
                        "{}: rtl",
                        self.label("app.terminal.textDirection.label")
                    ));
                }
                ui.text(output);
                let at_bottom = ui.scroll_y() >= (ui.scroll_max_y() - 4.0).max(0.0);
                if ui.is_window_hovered() && ui.io().mouse_wheel > 0.0 && !at_bottom {
                    self.terminal_autoscroll = false;
                } else if ui.is_window_hovered() && ui.io().mouse_wheel < 0.0 && at_bottom {
                    self.terminal_autoscroll = true;
                }
                if self.terminal_autoscroll {
                    ui.set_scroll_here_y_with_ratio(1.0);
                }
            });
    }

    fn localized_status_label(&self, status: TerminalStatus) -> String {
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

fn spinner(ui: &Ui) -> &'static str {
    const FRAMES: [&str; 8] = ["|", "/", "-", "\\", "|", "/", "-", "\\"];
    let frame = ((ui.time() * 8.0) as usize) % FRAMES.len();
    FRAMES[frame]
}

fn status_icon(status: TerminalStatus) -> &'static str {
    match status {
        TerminalStatus::Ready => ".",
        TerminalStatus::Running => "*",
        TerminalStatus::Ok => "OK",
        TerminalStatus::Warning => "!",
        TerminalStatus::Failed => "X",
    }
}

fn status_color(status: TerminalStatus) -> [f32; 4] {
    match status {
        TerminalStatus::Ready => [0.38, 0.42, 0.48, 1.0],
        TerminalStatus::Running => [0.16, 0.36, 0.82, 1.0],
        TerminalStatus::Ok => [0.10, 0.50, 0.22, 1.0],
        TerminalStatus::Warning => [0.75, 0.46, 0.08, 1.0],
        TerminalStatus::Failed => [0.75, 0.10, 0.10, 1.0],
    }
}

fn action_label(action: &ActionView, field_values: &BTreeMap<String, String>) -> String {
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

fn render_body_text(ui: &Ui, fonts: &ImGuiFonts, body: &str) {
    for line in body.lines() {
        if line.trim().is_empty() {
            ui.spacing();
        } else if let Some(title) = line.strip_prefix("## ") {
            render_section_heading(ui, fonts, title);
        } else {
            ui.text_wrapped(line);
        }
    }
}

fn render_section_heading(ui: &Ui, fonts: &ImGuiFonts, title: &str) {
    ui.separator();
    let section_font = ui.push_font(fonts.section);
    ui.text(title);
    section_font.pop();
}
