mod app_state;
mod app_values;
mod args;
mod metadata;
mod path_picker;
mod terminal;
mod ui;
mod ui_page;
mod ui_shared;
mod ui_sidebar;
mod ui_terminal;

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
#[path = "../../Slint/src/row_actions.rs"]
mod row_actions;
#[path = "../../Slint/src/state.rs"]
mod state;
#[path = "../../Slint/src/workspace.rs"]
mod workspace;

use anyhow::{Context, Result};
use app_state::AppState;
use args::parse_args;
use std::fs;
use std::time::Instant;

fn main() {
    if let Err(error) = run() {
        eprintln!("gui-for-cli-raygui: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let started = Instant::now();
    let args = parse_args()?;
    let check_only = args.check;
    let benchmark = args.benchmark;
    let once = args.once;
    let benchmark_output = args.benchmark_output.clone();
    let mut state = AppState::new(args).context("initialize Raygui app state")?;
    if check_only {
        println!(
            "Loaded {} pages, {} controls, {} actions, {} data sources from {}",
            state.pages.len(),
            state.control_count,
            state.action_count,
            state.data_source_count,
            state.bundle_root.display()
        );
        return Ok(());
    }

    let (mut rl, thread) = raylib::init()
        .size(1120, 720)
        .title("GUI for CLI Raygui")
        .resizable()
        .build();
    rl.set_target_fps(60);
    rl.set_exit_key(None);
    let mut benchmark_emitted = false;

    while !rl.window_should_close() {
        state.poll_completed_commands();
        state.handle_keyboard(&mut rl);

        let mut draw = rl.begin_drawing(&thread);
        ui::draw(&mut draw, &mut state);
        drop(draw);

        if benchmark && !benchmark_emitted {
            benchmark_emitted = true;
            let message = format!(
                "raygui content-ready-ms={:.1} pages={} controls={} actions={} data-sources={}",
                started.elapsed().as_secs_f64() * 1000.0,
                state.pages.len(),
                state.control_count,
                state.action_count,
                state.data_source_count
            );
            println!("{message}");
            if let Some(path) = &benchmark_output {
                fs::write(path, format!("{message}\n"))
                    .with_context(|| format!("write benchmark marker {}", path.display()))?;
            }
            if once {
                return Ok(());
            }
        }
    }

    Ok(())
}
