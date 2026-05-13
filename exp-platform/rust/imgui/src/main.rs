mod app;
mod args;
mod data_view;
mod state;
mod ui;
mod window;

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
#[path = "../../shared/src/terminal.rs"]
mod terminal;
#[path = "../../shared/src/workspace.rs"]
mod workspace;

use anyhow::Result;
use app::ImGuiApp;
use args::parse_args;

fn main() {
    if let Err(error) = run() {
        eprintln!("gui-for-cli-imgui: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let args = parse_args()?;
    let mut app = ImGuiApp::load(args)?;
    app.print_benchmark_if_requested();
    if app.once() {
        return Ok(());
    }
    window::run_window(app)
}
