use crate::app::EguiApp;
use eframe::egui;

impl eframe::App for EguiApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.poll_finished_commands();
        handle_font_shortcuts(ctx, self);
        ctx.set_pixels_per_point(self.font_scale);

        if self.sidebar_visible {
            if self.is_rtl() {
                egui::SidePanel::right("sidebar")
                    .resizable(true)
                    .default_width(280.0)
                    .width_range(220.0..=420.0)
                    .show(ctx, |ui| self.render_sidebar(ui));
            } else {
                egui::SidePanel::left("sidebar")
                    .resizable(true)
                    .default_width(280.0)
                    .width_range(220.0..=420.0)
                    .show(ctx, |ui| self.render_sidebar(ui));
            }
        }

        self.render_terminal_panel(ctx);
        egui::CentralPanel::default().show(ctx, |ui| self.render_page(ui));
        if !self.running_action_ids.is_empty() || !self.running_setup_indexes.is_empty() {
            ctx.request_repaint_after(std::time::Duration::from_millis(100));
        }
    }
}

fn handle_font_shortcuts(ctx: &egui::Context, app: &mut EguiApp) {
    let zoom_in =
        ctx.input_mut(|input| input.consume_key(egui::Modifiers::COMMAND, egui::Key::Equals));
    let zoom_out =
        ctx.input_mut(|input| input.consume_key(egui::Modifiers::COMMAND, egui::Key::Minus));
    if zoom_in {
        app.font_scale = (app.font_scale + 0.05).min(1.6);
    }
    if zoom_out {
        app.font_scale = (app.font_scale - 0.05).max(0.8);
    }
}
