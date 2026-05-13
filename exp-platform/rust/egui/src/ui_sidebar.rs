use crate::app::EguiApp;
use crate::control_text::setup_command_preview;
use eframe::egui;

impl EguiApp {
    pub fn render_sidebar(&mut self, ui: &mut egui::Ui) {
        ui.vertical(|ui| {
            ui.horizontal(|ui| {
                ui.heading(&self.title);
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if ui
                        .small_button(if self.is_rtl() { "→" } else { "←" })
                        .on_hover_text(self.label("app.sidebar.hide.label"))
                        .clicked()
                    {
                        self.sidebar_visible = false;
                    }
                });
            });
            if !self.summary.is_empty() {
                ui.label(&self.summary).on_hover_text(&self.summary);
            }
            ui.separator();
            self.render_setup_status(ui);
            ui.separator();
            self.render_standard_options(ui);
            ui.separator();
            self.render_navigation(ui);
        });
    }

    fn render_setup_status(&mut self, ui: &mut egui::Ui) {
        egui::CollapsingHeader::new(self.label("app.setup.status.title"))
            .default_open(true)
            .show(ui, |ui| {
                for line in &self.setup_lines {
                    ui.label(line);
                }
                for index in 0..self.setup_steps.len() {
                    let step = self.setup_steps[index].clone();
                    let running = self.running_setup_indexes.contains(&index);
                    let title = if running {
                        format!("⏳ {}", step.label)
                    } else {
                        format!(
                            "{}: {}",
                            self.label("app.setup.runButton.title"),
                            step.label
                        )
                    };
                    let response = ui.add_enabled(!running, egui::Button::new(title));
                    if response.clicked() {
                        self.start_setup(index);
                    }
                    response.on_hover_text(setup_command_preview(&step));
                    if running {
                        ui.label(
                            egui::RichText::new(self.label("app.setup.step.running")).strong(),
                        );
                    }
                }
            });
    }

    fn render_standard_options(&mut self, ui: &mut egui::Ui) {
        egui::CollapsingHeader::new(self.label("app.standardOptions.title"))
            .default_open(true)
            .show(ui, |ui| {
                ui.label(format!(
                    "{}: {}",
                    self.label("language.setting.label"),
                    self.label("language.name")
                ));
                ui.label(format!(
                    "{}: {} / {}: {}",
                    self.label("app.layoutDirection.label"),
                    self.interface_direction,
                    self.label("app.terminal.textDirection.label"),
                    self.terminal_text_direction
                ));
                let font_size_label = self.label("app.fontSize.label");
                ui.add(egui::Slider::new(&mut self.font_scale, 0.8..=1.6).text(font_size_label));
                if ui
                    .button(self.label("app.workspace.openButton.title"))
                    .on_hover_text(self.bundle_root.display().to_string())
                    .clicked()
                {
                    self.open_workspace();
                }
            });
    }

    fn render_navigation(&mut self, ui: &mut egui::Ui) {
        ui.label(egui::RichText::new(self.label("app.sidebar.pages.title")).strong());
        egui::ScrollArea::vertical().show(ui, |ui| {
            let pages = self
                .pages
                .iter()
                .map(|page| page.title.clone())
                .collect::<Vec<_>>();
            for (index, title) in pages.iter().enumerate() {
                if ui
                    .selectable_label(index == self.selected_page, title)
                    .on_hover_text(title)
                    .clicked()
                {
                    self.select_page(index);
                }
            }
        });
    }
}
