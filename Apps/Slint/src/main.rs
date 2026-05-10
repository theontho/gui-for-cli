mod args;
mod bundle;

use anyhow::{Context, Result, anyhow};
use args::{configure_default_renderer, parse_args};
use bundle::{PageView, load_bundle};
use slint::{ComponentHandle, ModelRc, SharedString, VecModel};
use std::rc::Rc;
use std::time::Instant;

slint::slint! {
    import { Button, ScrollView } from "std-widgets.slint";

    export struct PageTab {
        title: string,
    }

    export component AppWindow inherits Window {
        in property <string> window-title;
        in property <string> bundle-summary;
        in property <string> page-title;
        in property <string> page-summary;
        in property <string> page-body;
        in property <[PageTab]> pages;
        callback page-selected(int);

        title: root.window-title;
        width: 1120px;
        height: 720px;
        background: #f6f7fb;

        HorizontalLayout {
            padding: 16px;
            spacing: 16px;

            Rectangle {
                width: 260px;
                background: #ffffff;
                border-color: #d7dbe7;
                border-radius: 12px;

                VerticalLayout {
                    padding: 14px;
                    spacing: 10px;

                    Text {
                        text: root.window-title;
                        font-size: 22px;
                        font-weight: 700;
                        color: #1c2333;
                    }

                    Text {
                        text: root.bundle-summary;
                        wrap: word-wrap;
                        color: #566070;
                    }

                    Rectangle { height: 1px; background: #e4e7ef; }

                    ScrollView {
                        viewport-width: 232px;

                        VerticalLayout {
                            spacing: 8px;

                            for page[index] in root.pages : Button {
                                text: page.title;
                                clicked => {
                                    root.page-selected(index);
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                background: #ffffff;
                border-color: #d7dbe7;
                border-radius: 12px;

                VerticalLayout {
                    padding: 18px;
                    spacing: 12px;

                    Text {
                        text: root.page-title;
                        font-size: 26px;
                        font-weight: 700;
                        color: #1c2333;
                    }

                    Text {
                        text: root.page-summary;
                        wrap: word-wrap;
                        color: #566070;
                    }

                    Rectangle { height: 1px; background: #e4e7ef; }

                    ScrollView {
                        Text {
                            text: root.page-body;
                            wrap: word-wrap;
                            color: #263044;
                            font-size: 15px;
                        }
                    }
                }
            }
        }
    }
}

fn main() {
    if let Err(error) = run() {
        eprintln!("gui-for-cli-slint: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let started = Instant::now();
    let args = parse_args()?;
    let bundle = load_bundle(&args.bundle, &args.repo_root, &args.locale)?;
    let loaded_ms = started.elapsed().as_secs_f64() * 1000.0;
    configure_default_renderer();

    let page_tabs = bundle
        .pages
        .iter()
        .map(|page| PageTab {
            title: page.title.as_str().into(),
        })
        .collect::<Vec<_>>();
    let pages = Rc::new(bundle.pages);
    let first_page = pages
        .first()
        .ok_or_else(|| anyhow!("bundle has no pages"))?;

    let ui = AppWindow::new().context("create Slint window")?;
    ui.set_window_title(bundle.title.as_str().into());
    ui.set_bundle_summary(bundle.summary.as_str().into());
    ui.set_pages(ModelRc::new(Rc::new(VecModel::from(page_tabs))));
    set_page(&ui, first_page);

    let ui_weak = ui.as_weak();
    let pages_for_callback = pages.clone();
    ui.on_page_selected(move |index| {
        if let Some(ui) = ui_weak.upgrade() {
            if let Some(page) = pages_for_callback.get(index.max(0) as usize) {
                set_page(&ui, page);
            }
        }
    });

    let ready_ms = started.elapsed().as_secs_f64() * 1000.0;
    if args.benchmark {
        println!(
            "gfc-slint benchmark bundle_loaded_ms={loaded_ms:.1} ui_ready_ms={ready_ms:.1} pages={}",
            pages.len()
        );
    }

    if args.once {
        return Ok(());
    }

    ui.run().context("run Slint window")
}

fn set_page(ui: &AppWindow, page: &PageView) {
    ui.set_page_title(SharedString::from(page.title.as_str()));
    ui.set_page_summary(SharedString::from(page.summary.as_str()));
    ui.set_page_body(SharedString::from(page.body.as_str()));
}
