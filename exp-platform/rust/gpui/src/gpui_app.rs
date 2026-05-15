use crate::model::GpuiModel;
use anyhow::Result;
use gpui::{
    App, Application, Bounds, Context, IntoElement, Render, SharedString, Window, WindowBounds,
    WindowOptions, div, prelude::*, px, rgb, size,
};
use std::time::Instant;

pub struct GpuiSurface {
    model: GpuiModel,
    started: Instant,
    benchmark_printed: bool,
}

impl GpuiSurface {
    fn new(model: GpuiModel, started: Instant) -> Self {
        Self {
            model,
            started,
            benchmark_printed: false,
        }
    }

    fn next_page(&mut self, cx: &mut Context<Self>) {
        let len = self.model.pages.len().max(1);
        self.model.select_page((self.model.selected_page + 1) % len);
        cx.notify();
    }
}

impl Render for GpuiSurface {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        if !self.benchmark_printed {
            self.benchmark_printed = true;
            let ui_ready_ms = self.started.elapsed().as_secs_f64() * 1000.0;
            if let Err(error) = self.model.emit_surface_benchmark(ui_ready_ms) {
                eprintln!("gui-for-cli-gpui: benchmark output failed: {error:#}");
            }
        }

        let page = self.model.current_page().cloned();
        let page_title = page
            .as_ref()
            .map(|page| page.title.clone())
            .unwrap_or_else(|| "No pages".to_string());
        let control_rows = page
            .as_ref()
            .map(|page| {
                page.controls
                    .iter()
                    .take(8)
                    .map(|control| {
                        div()
                            .py_1()
                            .child(format!("{}: {}", control.label, control.kind))
                    })
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let actions = page
            .as_ref()
            .map(|page| {
                page.actions
                    .iter()
                    .take(6)
                    .map(|action| div().py_1().child(action.title.clone()))
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();

        div()
            .size_full()
            .bg(rgb(0xf7f7f7))
            .text_color(rgb(0x1f2933))
            .p_5()
            .flex()
            .flex_col()
            .gap_3()
            .child(
                div()
                    .text_xl()
                    .font_weight(gpui::FontWeight::BOLD)
                    .child(self.model.title.clone()),
            )
            .child(div().child(self.model.summary.clone()))
            .child(div().child(format!(
                "{} pages / {} controls / {} actions",
                self.model.pages.len(),
                self.model.control_count,
                self.model.action_count
            )))
            .child(
                div()
                    .flex()
                    .gap_3()
                    .child(
                        div()
                            .w(px(220.0))
                            .p_3()
                            .bg(rgb(0xffffff))
                            .border_1()
                            .border_color(rgb(0xd0d7de))
                            .rounded_md()
                            .child(div().font_weight(gpui::FontWeight::BOLD).child("Pages"))
                            .children(self.model.pages.iter().enumerate().map(|(index, page)| {
                                let selected = index == self.model.selected_page;
                                div()
                                    .id(SharedString::from(format!("page-{}", page.id)))
                                    .py_1()
                                    .text_color(if selected {
                                        rgb(0x0969da)
                                    } else {
                                        rgb(0x1f2933)
                                    })
                                    .child(page.title.clone())
                            })),
                    )
                    .child(
                        div()
                            .flex_1()
                            .p_3()
                            .bg(rgb(0xffffff))
                            .border_1()
                            .border_color(rgb(0xd0d7de))
                            .rounded_md()
                            .flex()
                            .flex_col()
                            .gap_2()
                            .child(
                                div()
                                    .text_lg()
                                    .font_weight(gpui::FontWeight::BOLD)
                                    .child(page_title),
                            )
                            .child(
                                div()
                                    .id("next-page")
                                    .cursor_pointer()
                                    .px_2()
                                    .py_1()
                                    .bg(rgb(0xe6f0ff))
                                    .rounded_sm()
                                    .child("Next page")
                                    .on_click(cx.listener(|this, _, _, cx| this.next_page(cx))),
                            )
                            .child(div().font_weight(gpui::FontWeight::BOLD).child("Controls"))
                            .children(control_rows)
                            .child(div().font_weight(gpui::FontWeight::BOLD).child("Actions"))
                            .children(actions),
                    ),
            )
    }
}

pub fn run_surface(model: GpuiModel, started: Instant) -> Result<()> {
    Application::new().run(move |cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(900.0), px(640.0)), cx);
        let window_result = cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                ..Default::default()
            },
            |_, cx| cx.new(|_| GpuiSurface::new(model, started)),
        );
        if let Err(error) = window_result {
            eprintln!("gui-for-cli-gpui: open GPUI window: {error:#}");
            std::process::exit(1);
        }
        cx.activate(true);
    });
    Ok(())
}
