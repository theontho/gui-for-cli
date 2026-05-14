#![allow(dead_code)]

mod args;
mod data_view;
mod metadata;
mod model;
mod model_benchmark;

#[cfg(test)]
mod model_tests;

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
use args::parse_args;
use model::{UI_BLOCKER, XilemModel};

fn main() {
    if let Err(error) = run() {
        eprintln!("gui-for-cli-xilem-vello: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let args = parse_args()?;
    let check = args.check;
    let benchmark = args.benchmark;
    let once = args.once;
    let benchmark_output = args.benchmark_output.clone();
    let mut model = XilemModel::load(args).context("initialize Xilem/Vello core renderer")?;

    if check {
        model.print_check_summary();
        if benchmark {
            model.emit_benchmark(benchmark_output.as_deref())?;
        }
        return Ok(());
    }

    if benchmark || once {
        model.emit_benchmark(benchmark_output.as_deref())?;
        return Ok(());
    }

    println!("{UI_BLOCKER}");
    model.print_check_summary();
    Ok(())
}
