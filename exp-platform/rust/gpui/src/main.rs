#![allow(dead_code)]

mod args;
mod data_view;
mod localization;
mod metadata;
mod model;
mod model_benchmark;
#[cfg(test)]
mod model_tests;

#[cfg(test)]
pub(crate) static WGS_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

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

use anyhow::{Context as AnyhowContext, Result};
use args::parse_args;
use model::GpuiModel;

fn main() {
    if let Err(error) = run() {
        eprintln!("gui-for-cli-gpui: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let args = parse_args()?;
    let check_only = args.check;
    let benchmark = args.benchmark;
    let once = args.once;
    let model = GpuiModel::load(args).context("initialize GPUI renderer state")?;

    if check_only {
        model.print_check_summary();
        if benchmark {
            model.print_benchmark_summary()?;
        }
        return Ok(());
    }

    if benchmark || once {
        model.print_benchmark_summary()?;
        return Ok(());
    }

    eprintln!(
        "gui-for-cli-gpui: running in headless/core mode; the GPUI window is blocked by the current gpui crate Metal shader build failure on macOS. Use --check or --benchmark --once for CI validation."
    );
    model.print_check_summary();
    Ok(())
}

#[cfg(test)]
mod integration_tests {
    use super::*;
    use crate::args::Args;
    use std::path::PathBuf;

    #[test]
    fn loads_wgs_bundle_into_core_state() {
        let _guard = crate::WGS_TEST_LOCK.lock().expect("lock WGS workspace");
        let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .ancestors()
            .nth(3)
            .expect("repo root")
            .to_path_buf();
        let args = Args {
            bundle: repo_root.join("examples/WGSExtract"),
            repo_root,
            locale: "en".to_string(),
            check: false,
            benchmark: false,
            benchmark_full: false,
            once: false,
            benchmark_output: None,
        };

        let model = GpuiModel::load(args).expect("load model");

        assert!(model.pages.len() >= 4);
        assert!(model.control_count > 0);
        assert!(model.action_count > 0);
        assert_eq!(model.terminal_text_direction, "ltr");
    }
}
