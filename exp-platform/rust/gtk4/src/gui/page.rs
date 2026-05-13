use crate::app_model::GtkAppModel;
use crate::gui::{controls, refresh_window};
use crate::snapshot::{ActionSnapshot, UiSnapshot};
use gtk::glib;
use gtk::prelude::*;
use std::cell::RefCell;
use std::rc::Rc;

pub fn build(
    snapshot: &UiSnapshot,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) -> gtk::ScrolledWindow {
    let content = gtk::Box::new(gtk::Orientation::Vertical, 14);
    content.set_margin_top(18);
    content.set_margin_bottom(18);
    content.set_margin_start(18);
    content.set_margin_end(18);

    if let Some(page) = &snapshot.current_page {
        let title = gtk::Label::new(Some(&page.title));
        title.set_xalign(0.0);
        title.set_wrap(true);
        title.add_css_class("title-1");
        content.append(&title);
        if !page.summary.is_empty() {
            content.append(&wrapped_muted(&page.summary));
        }
        if !page.body.is_empty() {
            let body = wrapped_muted(&page.body);
            body.set_selectable(true);
            content.append(&body);
        }
    }

    for control in &snapshot.controls {
        content.append(&controls::build(
            control,
            &snapshot.labels,
            model.clone(),
            weak_window.clone(),
        ));
    }

    if !snapshot.actions.is_empty() {
        let actions_label = gtk::Label::new(Some(&label(snapshot, "app.actionsColumn.title")));
        actions_label.set_xalign(0.0);
        actions_label.add_css_class("title-3");
        content.append(&actions_label);
        let action_box = gtk::FlowBox::new();
        action_box.set_selection_mode(gtk::SelectionMode::None);
        action_box.set_max_children_per_line(4);
        for action in &snapshot.actions {
            action_box.insert(
                &action_button(action, model.clone(), weak_window.clone()),
                -1,
            );
        }
        content.append(&action_box);
    }

    gtk::ScrolledWindow::builder()
        .hexpand(true)
        .vexpand(true)
        .child(&content)
        .build()
}

fn action_button(
    action: &ActionSnapshot,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) -> gtk::Button {
    let label = if action.running {
        format!("⏳ {}", action.action.title)
    } else {
        action.action.title.clone()
    };
    let button = gtk::Button::with_label(&label);
    button.set_tooltip_text(Some(
        action
            .disabled_reason
            .as_deref()
            .unwrap_or(action.preview.as_str()),
    ));
    button.set_sensitive(action.disabled_reason.is_none() && !action.running);
    if action.action.role == "destructive" {
        button.add_css_class("destructive-action");
    }
    let action = action.action.clone();
    button.connect_clicked(move |_| {
        model.borrow_mut().start_action(action.clone());
        refresh_window(&weak_window, model.clone());
    });
    button
}

fn wrapped_muted(text: &str) -> gtk::Label {
    let label = gtk::Label::new(Some(text));
    label.set_xalign(0.0);
    label.set_wrap(true);
    label.add_css_class("gfc-muted");
    label
}

fn label(snapshot: &UiSnapshot, key: &str) -> String {
    snapshot
        .labels
        .get(key)
        .cloned()
        .unwrap_or_else(|| key.to_string())
}
