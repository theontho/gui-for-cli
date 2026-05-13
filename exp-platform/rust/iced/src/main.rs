mod app;
mod app_benchmark;
mod args;
mod data_view;
mod messages;
mod metadata;
mod ui;
mod ui_controls;
mod ui_sidebar;
mod ui_terminal;
mod view_values;

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

use anyhow::{Context, Result};
use app::IcedApp;
use args::parse_args;
use iced::{Settings, Size, Task, window};

fn main() {
    if let Err(error) = run() {
        eprintln!("gui-for-cli-iced: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let args = parse_args()?;
    let check_only = args.check;
    let benchmark_once = args.benchmark && args.once;
    let app = IcedApp::load(args).context("initialize Iced app state")?;

    if check_only {
        app.print_check_summary();
        if app.benchmark_enabled() {
            app.print_benchmark_summary()?;
        }
        return Ok(());
    }

    if benchmark_once {
        app.print_benchmark_summary()?;
        return Ok(());
    }

    let window = window::Settings {
        size: Size::new(1180.0, 760.0),
        min_size: Some(Size::new(760.0, 520.0)),
        ..window::Settings::default()
    };

    iced::application(
        |state: &IcedApp| state.window_title(),
        IcedApp::update,
        IcedApp::view,
    )
    .theme(IcedApp::theme)
    .window(window)
    .settings(Settings::default())
    .run_with(move || (app, Task::none()))
    .context("run Iced window")
}
