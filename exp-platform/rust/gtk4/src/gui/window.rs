use crate::app_model::GtkAppModel;
use crate::gui::{page, refresh_window, sidebar, terminal};
use adw::prelude::*;
use gtk::glib;
use gtk::prelude::*;
use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

const CSS: &str = r#"
.gfc-sidebar { background: @view_bg_color; padding: 12px; }
.gfc-card { padding: 12px; border-radius: 12px; background: @card_bg_color; }
.gfc-muted { color: @dim_label_color; }
.gfc-terminal textview { font-family: monospace; }
.gfc-status-running { color: @accent_color; }
.gfc-status-warning { color: @warning_color; }
.gfc-status-failed { color: @error_color; }
"#;

#[derive(Clone, Copy)]
struct LayoutPositions {
    root: i32,
    detail: Option<i32>,
}

pub fn build(application: &adw::Application, model: Rc<RefCell<GtkAppModel>>) {
    install_css();
    let title = model.borrow_mut().snapshot().title;
    let window = adw::ApplicationWindow::builder()
        .application(application)
        .title(&title)
        .default_width(1240)
        .default_height(780)
        .build();
    render(&window, model.clone());
    let weak_window = window.downgrade();
    let tick_model = model.clone();
    glib::timeout_add_local(Duration::from_millis(350), move || {
        if weak_window.upgrade().is_none() {
            return glib::ControlFlow::Break;
        }
        if tick_model.borrow().has_running_commands() {
            refresh_window(&weak_window, tick_model.clone());
        }
        glib::ControlFlow::Continue
    });
    if std::env::var("GFC_BENCHMARK_PRESERVE_FOCUS").as_deref() == Ok("1") {
        window.set_visible(true);
    } else {
        window.present();
    }
}

pub fn render(window: &adw::ApplicationWindow, model: Rc<RefCell<GtkAppModel>>) {
    let snapshot = model.borrow_mut().snapshot();
    let positions = capture_layout_positions(window);
    window.set_title(Some(&snapshot.title));
    let root = gtk::Paned::new(gtk::Orientation::Horizontal);
    root.set_wide_handle(true);
    root.set_position(positions.map(|positions| positions.root).unwrap_or(300));
    root.set_direction(if snapshot.is_rtl {
        gtk::TextDirection::Rtl
    } else {
        gtk::TextDirection::Ltr
    });

    let weak_window = window.downgrade();
    let sidebar = sidebar::build(&snapshot, model.clone(), weak_window.clone());
    let detail = detail_pane(
        &snapshot,
        model,
        weak_window,
        positions.and_then(|p| p.detail),
    );
    if snapshot.is_rtl {
        root.set_start_child(Some(&detail));
        root.set_end_child(Some(&sidebar));
    } else {
        root.set_start_child(Some(&sidebar));
        root.set_end_child(Some(&detail));
    }
    root.set_resize_start_child(false);
    root.set_shrink_start_child(false);
    window.set_content(Some(&root));
}

fn detail_pane(
    snapshot: &crate::snapshot::UiSnapshot,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
    position: Option<i32>,
) -> gtk::Box {
    let detail = gtk::Box::new(gtk::Orientation::Vertical, 0);
    let split = gtk::Paned::new(gtk::Orientation::Vertical);
    split.set_position(position.unwrap_or(560));
    split.set_wide_handle(true);
    split.set_start_child(Some(&page::build(
        snapshot,
        model.clone(),
        weak_window.clone(),
    )));
    split.set_end_child(Some(&terminal::build(snapshot, model, weak_window)));
    split.set_resize_start_child(true);
    split.set_resize_end_child(false);
    detail.append(&split);
    detail
}

fn capture_layout_positions(window: &adw::ApplicationWindow) -> Option<LayoutPositions> {
    let root = window.child()?.downcast::<gtk::Paned>().ok()?;
    Some(LayoutPositions {
        root: root.position(),
        detail: nested_paned_position(&root, gtk::Orientation::Vertical),
    })
}

fn nested_paned_position(root: &gtk::Paned, orientation: gtk::Orientation) -> Option<i32> {
    [root.start_child(), root.end_child()]
        .into_iter()
        .flatten()
        .find_map(|child| widget_paned_position(&child, orientation))
}

fn widget_paned_position(widget: &gtk::Widget, orientation: gtk::Orientation) -> Option<i32> {
    if let Ok(paned) = widget.clone().downcast::<gtk::Paned>() {
        if paned.orientation() == orientation {
            return Some(paned.position());
        }
        return nested_paned_position(&paned, orientation);
    }

    let mut child = widget.first_child();
    while let Some(current) = child {
        if let Some(position) = widget_paned_position(&current, orientation) {
            return Some(position);
        }
        child = current.next_sibling();
    }
    None
}

fn install_css() {
    let Some(display) = gtk::gdk::Display::default() else {
        return;
    };
    let provider = gtk::CssProvider::new();
    provider.load_from_data(CSS);
    gtk::style_context_add_provider_for_display(
        &display,
        &provider,
        gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
}
