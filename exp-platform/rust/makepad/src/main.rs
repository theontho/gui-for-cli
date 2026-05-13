pub use makepad_widgets;

mod app;
mod content;
mod model;

#[allow(dead_code)]
#[path = "../../shared/src/args.rs"]
mod args;
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

fn main() {
    if std::env::args().any(|arg| arg == "--once") {
        if let Err(error) = run_once() {
            eprintln!("gui-for-cli-makepad: {error:#}");
            std::process::exit(1);
        }
        return;
    }
    app::app_main();
}

fn run_once() -> anyhow::Result<()> {
    let args = args::parse_args()?;
    let mut model = model::MakepadModel::load(args)?;
    model.print_benchmark_if_requested();
    Ok(())
}
