mod app;
mod args;
mod data_view;
mod state;
mod ui;
mod window;

#[path = "../../Slint/src/bundle.rs"]
mod bundle;
#[path = "../../Slint/src/control_text.rs"]
mod control_text;
#[path = "../../Slint/src/data_source_cache.rs"]
mod data_source_cache;
#[path = "../../Slint/src/execution.rs"]
mod execution;
#[path = "../../Slint/src/exit_codes.rs"]
mod exit_codes;
#[path = "../../Slint/src/path_picker.rs"]
mod path_picker;
#[path = "../../Slint/src/row_actions.rs"]
mod row_actions;
#[path = "../../Slint/src/terminal.rs"]
mod terminal;
#[path = "../../Slint/src/workspace.rs"]
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
