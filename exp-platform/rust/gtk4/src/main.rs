#![cfg_attr(not(feature = "gtk-ui"), allow(dead_code))]

mod app_model;
mod snapshot;

#[cfg(feature = "gtk-ui")]
mod gui;

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

use anyhow::{Result, anyhow};
use app_model::GtkAppModel;
use args::parse_args;

fn main() {
    if let Err(error) = run() {
        eprintln!("gui-for-cli-gtk4: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let args = parse_args()?;
    let mut model = GtkAppModel::load(args)?;
    model.print_benchmark_if_requested();
    if model.once() {
        return Ok(());
    }
    run_ui(model)
}

#[cfg(feature = "gtk-ui")]
fn run_ui(model: GtkAppModel) -> Result<()> {
    gui::run(model)
}

#[cfg(not(feature = "gtk-ui"))]
fn run_ui(_model: GtkAppModel) -> Result<()> {
    Err(anyhow!(
        "GTK4 UI support was not compiled. Build with `cargo run --features gtk-ui --manifest-path exp-platform/rust/gtk4/Cargo.toml -- --bundle examples/WGSExtract`."
    ))
}
