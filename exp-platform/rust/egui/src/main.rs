mod app;
mod args;
mod data_view;
mod ui;
mod ui_page;
mod ui_sidebar;
mod ui_terminal;
mod ui_widgets;

#[path = "../../shared/src/bundle.rs"]
mod bundle;
#[path = "../../shared/src/control_text.rs"]
mod control_text;
#[path = "../../shared/src/data_source_cache.rs"]
mod data_source_cache;
#[path = "../../shared/src/execution.rs"]
mod execution;
#[path = "../../shared/src/exit_codes.rs"]
mod exit_codes;
#[path = "../../shared/src/path_picker.rs"]
mod path_picker;
#[path = "../../shared/src/row_actions.rs"]
mod row_actions;
#[path = "../../shared/src/state.rs"]
mod state;
#[path = "../../shared/src/terminal.rs"]
mod terminal;
#[path = "../../shared/src/workspace.rs"]
mod workspace;

use anyhow::Result;
use app::EguiApp;
use args::parse_args;

fn main() {
    if let Err(error) = run() {
        eprintln!("gui-for-cli-egui: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let args = parse_args()?;
    let check = args.check;
    let benchmark = args.benchmark;
    let once = args.once;
    let benchmark_output = args.benchmark_output.clone();
    let mut app = EguiApp::load(args)?;

    if check {
        println!(
            "Loaded {} pages, {} controls, {} actions, {} data sources from {}",
            app.pages.len(),
            app.control_count,
            app.action_count,
            app.data_source_count,
            app.bundle_root.display()
        );
        return Ok(());
    }

    if benchmark || once {
        app.emit_benchmark(benchmark_output.as_deref())?;
        return Ok(());
    }

    let title = app.title().to_string();
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title(title)
            .with_inner_size([1180.0, 760.0])
            .with_min_inner_size([780.0, 520.0]),
        ..Default::default()
    };
    eframe::run_native(
        "GUI for CLI egui",
        options,
        Box::new(|creation_context| {
            configure_egui(&creation_context.egui_ctx);
            Ok(Box::new(app))
        }),
    )
    .map_err(|error| anyhow::anyhow!(error.to_string()))
}

fn configure_egui(ctx: &egui::Context) {
    let mut style = (*ctx.style()).clone();
    style.spacing.item_spacing = egui::vec2(8.0, 8.0);
    style.spacing.button_padding = egui::vec2(10.0, 6.0);
    style.visuals.widgets.noninteractive.bg_stroke.color = egui::Color32::from_gray(210);
    ctx.set_style(style);
}
