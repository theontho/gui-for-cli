use crate::model::XilemModel;
use anyhow::{Context, Result};
use masonry::properties::types::AsUnit;
use std::fs;
use std::path::PathBuf;
use std::time::Instant;
use winit::dpi::LogicalSize;
use winit::error::EventLoopError;
use xilem::style::Style as _;
use xilem::view::{
    CrossAxisAlignment, FlexSpacer, MainAxisAlignment, flex_col, flex_row, label, sized_box,
    text_button,
};
use xilem::{EventLoop, WidgetView, WindowOptions, Xilem};

pub struct XilemSurface {
    model: XilemModel,
    started: Instant,
    benchmark_enabled: bool,
    benchmark_output: Option<PathBuf>,
    benchmark_printed: bool,
}

impl XilemSurface {
    pub fn new(
        model: XilemModel,
        started: Instant,
        benchmark_enabled: bool,
        benchmark_output: Option<PathBuf>,
    ) -> Self {
        Self {
            model,
            started,
            benchmark_enabled,
            benchmark_output,
            benchmark_printed: false,
        }
    }
}

pub fn run_surface(
    model: XilemModel,
    started: Instant,
    benchmark_enabled: bool,
    benchmark_output: Option<PathBuf>,
) -> Result<()> {
    let title = model.title.clone();
    let app = Xilem::new_simple(
        XilemSurface::new(model, started, benchmark_enabled, benchmark_output),
        app_logic,
        WindowOptions::new(title)
            .with_min_inner_size(LogicalSize::new(960.0, 640.0))
            .with_initial_inner_size(LogicalSize::new(1280.0, 840.0)),
    );
    app.run_in(EventLoop::with_user_event())
        .map_err(event_loop_error)
}

fn app_logic(state: &mut XilemSurface) -> impl WidgetView<XilemSurface> + use<> {
    if state.benchmark_enabled && !state.benchmark_printed {
        state.benchmark_printed = true;
        if let Err(error) = emit_benchmark(state) {
            eprintln!("gui-for-cli-xilem-vello: benchmark output failed: {error:#}");
        }
    }

    let selected_page_index = state.model.selected_page;
    let page_buttons = state
        .model
        .pages
        .iter()
        .enumerate()
        .map(|(index, page)| {
            let title = if index == selected_page_index {
                format!("• {}", page.title)
            } else {
                page.title.clone()
            };
            text_button(title, move |state: &mut XilemSurface| {
                state.model.select_page(index);
            })
        })
        .collect::<Vec<_>>();

    let current_page = state.model.current_page().cloned();
    let page_summary = current_page
        .as_ref()
        .map(|page| page.summary.clone())
        .unwrap_or_else(|| "No pages are available in this bundle.".to_string());
    let control_lines = current_page
        .as_ref()
        .map(|page| {
            page.controls
                .iter()
                .take(10)
                .map(|control| {
                    let value = state.model.control_value(control);
                    let details = state.model.control_details(control);
                    let value = if value.is_empty() {
                        "empty".to_string()
                    } else {
                        value
                    };
                    if details.is_empty() {
                        format!("{} · {} · {}", control.label, control.kind, value)
                    } else {
                        format!(
                            "{} · {} · {} · {}",
                            control.label, control.kind, value, details
                        )
                    }
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let actions = current_page
        .as_ref()
        .map(|page| {
            let values = state.model.effective_field_values(page);
            state.model.visible_actions(page, &values)
        })
        .unwrap_or_default();
    let action_buttons = actions
        .iter()
        .take(8)
        .map(|action| {
            let action = action.clone();
            text_button(action.title.clone(), move |state: &mut XilemSurface| {
                state.model.start_action(action.clone());
            })
        })
        .collect::<Vec<_>>();
    let control_labels = if control_lines.is_empty() {
        vec![detail_line("No controls on this page.".to_string())]
    } else {
        control_lines
            .into_iter()
            .map(detail_line)
            .collect::<Vec<_>>()
    };

    sized_box(
        flex_col((
            flex_col((
                label(state.model.title.clone()).text_size(28.0),
                label(state.model.summary.clone()).text_size(15.0),
                label(format!(
                    "{} pages · {} controls · {} actions · {} data sources",
                    state.model.pages.len(),
                    state.model.control_count,
                    state.model.action_count,
                    state.model.data_source_count,
                ))
                .text_size(14.0),
            ))
            .gap(8.px()),
            flex_row((
                sized_box(flex_col(page_buttons).gap(6.px()))
                    .width(280.px())
                    .padding(12.0),
                sized_box(
                    flex_col((
                        current_page
                            .as_ref()
                            .map(|page| label(page.title.clone()).text_size(24.0))
                            .unwrap_or_else(|| label("No page selected").text_size(24.0)),
                        label(page_summary).text_size(15.0),
                        label("Controls").text_size(18.0),
                        flex_col(control_labels).gap(4.px()),
                        label("Actions").text_size(18.0),
                        flex_row(action_buttons).gap(8.px()),
                        label(format!(
                            "Terminal: {} tabs · {} visible",
                            state.model.terminal.entries().len(),
                            if state.model.terminal_visible {
                                "shown"
                            } else {
                                "hidden"
                            }
                        ))
                        .text_size(14.0),
                    ))
                    .gap(10.px()),
                )
                .width(900.px()),
            ))
            .gap(16.px()),
            flex_row((
                text_button("Previous page", |state: &mut XilemSurface| {
                    let len = state.model.pages.len().max(1);
                    state
                        .model
                        .select_page((state.model.selected_page + len - 1) % len);
                }),
                text_button("Next page", |state: &mut XilemSurface| {
                    let len = state.model.pages.len().max(1);
                    state
                        .model
                        .select_page((state.model.selected_page + 1) % len);
                }),
                FlexSpacer::Flex(1.0),
            ))
            .gap(8.px())
            .cross_axis_alignment(CrossAxisAlignment::Center)
            .main_axis_alignment(MainAxisAlignment::Start),
        ))
        .gap(18.px()),
    )
    .padding(18.0)
}

fn detail_line(text: String) -> impl WidgetView<XilemSurface> {
    label(text).text_size(14.0)
}

fn emit_benchmark(state: &mut XilemSurface) -> Result<()> {
    if state.model.benchmark_full {
        state.model.warm_all_pages();
    }
    let ui_ready_ms = state.started.elapsed().as_secs_f64() * 1000.0;
    let message = format!(
        "metric ui_ready_ms={ui_ready_ms:.3}\nmetric bundle_loaded_ms={:.3}\nmetric pages={}\nmetric controls={}\nmetric actions={}\nmetric surface=xilem-vello",
        state.model.loaded_ms,
        state.model.pages.len(),
        state.model.control_count,
        state.model.action_count,
    );
    println!("{message}");
    if let Some(path) = &state.benchmark_output {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
        }
        fs::write(path, format!("{message}\n"))
            .with_context(|| format!("write benchmark marker {}", path.display()))?;
    }
    Ok(())
}

fn event_loop_error(error: EventLoopError) -> anyhow::Error {
    anyhow::anyhow!("run Xilem/Vello event loop: {error}")
}
