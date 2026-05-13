use crate::app_model::GtkAppModel;
use crate::gui::refresh_window;
use crate::snapshot::UiSnapshot;
use crate::terminal::TerminalStatus;
use gtk::glib;
use gtk::prelude::*;
use std::cell::RefCell;
use std::rc::Rc;

pub fn build(
    snapshot: &UiSnapshot,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) -> gtk::Box {
    let outer = gtk::Box::new(gtk::Orientation::Vertical, 6);
    outer.add_css_class("gfc-terminal");
    let bar = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let title = gtk::Label::new(Some(&label(snapshot, "app.terminal.commandOutput.label")));
    title.set_xalign(0.0);
    title.set_hexpand(true);
    bar.append(&title);
    let toggle = gtk::Button::with_label(if snapshot.terminal_visible {
        &label(snapshot, "app.terminal.hideOutput.label")
    } else {
        &label(snapshot, "app.terminal.showOutput.label")
    });
    let toggle_model = model.clone();
    let toggle_weak = weak_window.clone();
    toggle.connect_clicked(move |_| {
        toggle_model.borrow_mut().toggle_terminal();
        refresh_window(&toggle_weak, toggle_model.clone());
    });
    bar.append(&toggle);
    outer.append(&bar);
    if !snapshot.terminal_visible {
        return outer;
    }

    let notebook = gtk::Notebook::new();
    notebook.set_hexpand(true);
    notebook.set_vexpand(true);
    notebook.set_tab_pos(gtk::PositionType::Top);
    for (index, entry) in snapshot.terminal_entries.iter().enumerate() {
        let view = terminal_text(&entry.output, snapshot.terminal_text_direction.as_str());
        let tab = tab_label(index, snapshot, model.clone(), weak_window.clone());
        notebook.append_page(&view, Some(&tab));
    }
    notebook.set_current_page(Some(snapshot.selected_terminal as u32));
    notebook.connect_switch_page(move |_, _, page| {
        model.borrow_mut().select_terminal(page as usize);
    });
    outer.append(&notebook);
    outer
}

fn terminal_text(output: &str, direction: &str) -> gtk::ScrolledWindow {
    let buffer = gtk::TextBuffer::new(None::<&gtk::TextTagTable>);
    buffer.set_text(output);
    let view = gtk::TextView::new();
    view.set_buffer(Some(&buffer));
    view.set_editable(false);
    view.set_cursor_visible(false);
    view.set_monospace(true);
    view.set_wrap_mode(gtk::WrapMode::WordChar);
    view.set_direction(if direction == "rtl" {
        gtk::TextDirection::Rtl
    } else {
        gtk::TextDirection::Ltr
    });
    let mut end = buffer.end_iter();
    view.scroll_to_iter(&mut end, 0.0, false, 0.0, 1.0);
    gtk::ScrolledWindow::builder()
        .min_content_height(180)
        .hexpand(true)
        .vexpand(true)
        .child(&view)
        .build()
}

fn tab_label(
    index: usize,
    snapshot: &UiSnapshot,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) -> gtk::Box {
    let entry = &snapshot.terminal_entries[index];
    let box_ = gtk::Box::new(gtk::Orientation::Horizontal, 4);
    let label = gtk::Label::new(Some(&format!("{} · {}", entry.title, status(entry.status))));
    label.add_css_class(status_class(entry.status));
    box_.append(&label);
    if entry.closable {
        let title = if entry.status == TerminalStatus::Running {
            label_key(snapshot, "app.terminal.cancelButton.title", "Cancel")
        } else {
            label_key(snapshot, "app.terminal.closeButton.title", "Close")
        };
        let close = gtk::Button::with_label(&title);
        close.add_css_class("flat");
        close.connect_clicked(move |_| {
            model.borrow_mut().handle_terminal_action(index);
            refresh_window(&weak_window, model.clone());
        });
        box_.append(&close);
    }
    box_
}

fn status(status: TerminalStatus) -> &'static str {
    match status {
        TerminalStatus::Ready => "Ready",
        TerminalStatus::Running => "Running",
        TerminalStatus::Ok => "OK",
        TerminalStatus::Warning => "Warning",
        TerminalStatus::Failed => "Failed",
    }
}

fn status_class(status: TerminalStatus) -> &'static str {
    match status {
        TerminalStatus::Running => "gfc-status-running",
        TerminalStatus::Warning => "gfc-status-warning",
        TerminalStatus::Failed => "gfc-status-failed",
        _ => "gfc-muted",
    }
}

fn label(snapshot: &UiSnapshot, key: &str) -> String {
    label_key(snapshot, key, key)
}

fn label_key(snapshot: &UiSnapshot, key: &str, fallback: &str) -> String {
    snapshot
        .labels
        .get(key)
        .cloned()
        .unwrap_or_else(|| fallback.to_string())
}
