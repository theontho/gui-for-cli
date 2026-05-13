use crate::app_model::GtkAppModel;
use crate::gui::refresh_window;
use crate::row_actions::{DataSourceRowActionView, DataSourceRowView};
use crate::snapshot::ControlSnapshot;
use gtk::glib;
use gtk::prelude::*;
use std::cell::RefCell;
use std::collections::BTreeMap;
use std::collections::BTreeSet;
use std::rc::Rc;

pub fn build(
    snapshot: &ControlSnapshot,
    labels: &BTreeMap<String, String>,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) -> gtk::Box {
    let card = gtk::Box::new(gtk::Orientation::Vertical, 8);
    card.add_css_class("gfc-card");
    let label = gtk::Label::new(Some(&snapshot.control.label));
    label.set_xalign(0.0);
    label.add_css_class("heading");
    card.append(&label);
    match snapshot.control.kind.as_str() {
        "toggle" => card.append(&toggle(snapshot, model, weak_window)),
        "dropdown" if !snapshot.control.option_items.is_empty() => {
            card.append(&dropdown(snapshot, model, weak_window));
        }
        "checkboxGroup" if !snapshot.control.option_items.is_empty() => {
            card.append(&checkbox_group(snapshot, model, weak_window));
        }
        "path" => card.append(&path_entry(snapshot, labels, model, weak_window)),
        "text" | "dropdown" | "checkboxGroup" => {
            card.append(&text_entry(snapshot, model, weak_window))
        }
        _ => {}
    }
    if !snapshot.control.helper.is_empty() {
        card.append(&muted_label(&snapshot.control.helper));
    }
    render_rows_or_detail(&card, snapshot, labels, model, weak_window);
    card
}

fn text_entry(
    snapshot: &ControlSnapshot,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) -> gtk::Entry {
    let entry = gtk::Entry::new();
    entry.set_text(&snapshot.value);
    entry.set_placeholder_text(Some(&snapshot.control.placeholder));
    entry.set_direction(gtk::TextDirection::Ltr);
    let control_id = snapshot.control.id.clone();
    entry.connect_changed(move |entry| {
        model
            .borrow_mut()
            .set_control_value_by_id(&control_id, entry.text().as_str().to_string());
        refresh_window(&weak_window, model.clone());
    });
    entry
}

fn path_entry(
    snapshot: &ControlSnapshot,
    labels: &BTreeMap<String, String>,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) -> gtk::Box {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let entry = text_entry(snapshot, model.clone(), weak_window.clone());
    entry.set_hexpand(true);
    row.append(&entry);
    let browse = gtk::Button::with_label(&label(labels, "app.pathPicker.chooseButton.title"));
    let control_id = snapshot.control.id.clone();
    browse.connect_clicked(move |_| {
        model.borrow_mut().pick_control_path(&control_id);
        refresh_window(&weak_window, model.clone());
    });
    row.append(&browse);
    row
}

fn toggle(
    snapshot: &ControlSnapshot,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) -> gtk::CheckButton {
    let check = gtk::CheckButton::with_label(&snapshot.control.label);
    check.set_active(snapshot.value == "true");
    let control_id = snapshot.control.id.clone();
    check.connect_toggled(move |check| {
        model
            .borrow_mut()
            .set_control_value_by_id(&control_id, check.is_active().to_string());
        refresh_window(&weak_window, model.clone());
    });
    check
}

fn dropdown(
    snapshot: &ControlSnapshot,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) -> gtk::ComboBoxText {
    let combo = gtk::ComboBoxText::new();
    for option in &snapshot.control.option_items {
        combo.append(Some(&option.id), &option.title);
    }
    combo.set_active_id(Some(&snapshot.value));
    let control_id = snapshot.control.id.clone();
    combo.connect_changed(move |combo| {
        if let Some(value) = combo.active_id() {
            model
                .borrow_mut()
                .set_control_value_by_id(&control_id, value.as_str().to_string());
            refresh_window(&weak_window, model.clone());
        }
    });
    combo
}

fn checkbox_group(
    snapshot: &ControlSnapshot,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) -> gtk::Box {
    let group = gtk::Box::new(gtk::Orientation::Vertical, 4);
    let selected = snapshot
        .value
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
        .collect::<BTreeSet<_>>();
    for option in &snapshot.control.option_items {
        let check = gtk::CheckButton::with_label(&option.title);
        check.set_active(selected.contains(&option.id));
        let control_id = snapshot.control.id.clone();
        let option_id = option.id.clone();
        let current = selected.clone();
        let model = model.clone();
        let weak_window = weak_window.clone();
        check.connect_toggled(move |check| {
            let mut next = current.clone();
            if check.is_active() {
                next.insert(option_id.clone());
            } else {
                next.remove(&option_id);
            }
            model.borrow_mut().set_control_value_by_id(
                &control_id,
                next.iter().cloned().collect::<Vec<_>>().join(","),
            );
            refresh_window(&weak_window, model.clone());
        });
        group.append(&check);
    }
    group
}

fn render_rows_or_detail(
    card: &gtk::Box,
    snapshot: &ControlSnapshot,
    labels: &BTreeMap<String, String>,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) {
    match &snapshot.rows {
        Ok(rows) if !rows.is_empty() => {
            for row in rows.iter().take(30) {
                card.append(&data_row(row, model.clone(), weak_window.clone()));
            }
            if rows.len() > 30 {
                card.append(&muted_label(&format!("+{} more rows", rows.len() - 30)));
            }
        }
        Err(error) => card.append(&muted_label(&format!(
            "{}: {error}",
            label(labels, "app.dataSource.error.title")
        ))),
        _ if !snapshot.detail.is_empty() => card.append(&muted_label(&snapshot.detail)),
        _ => {}
    }
}

fn data_row(
    row: &DataSourceRowView,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) -> gtk::Box {
    let box_ = gtk::Box::new(gtk::Orientation::Vertical, 4);
    box_.set_margin_top(6);
    let title = if row.status.is_empty() {
        row.label.clone()
    } else {
        format!("{} · {}", row.label, row.status)
    };
    let label = gtk::Label::new(Some(&title));
    label.set_xalign(0.0);
    label.set_wrap(true);
    box_.append(&label);
    if !row.tags.is_empty() {
        box_.append(&muted_label(&row.tags.join(" · ")));
    }
    if !row.values.is_empty() {
        let values = row
            .values
            .iter()
            .take(6)
            .map(|(key, value)| format!("{key}: {value}"))
            .collect::<Vec<_>>()
            .join("  ");
        box_.append(&muted_label(&values));
    }
    if !row.actions.is_empty() {
        let actions = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        for action in &row.actions {
            actions.append(&row_action_button(
                action,
                model.clone(),
                weak_window.clone(),
            ));
        }
        box_.append(&actions);
    }
    box_
}

fn row_action_button(
    row_action: &DataSourceRowActionView,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) -> gtk::Button {
    let button = gtk::Button::with_label(&row_action.action.title);
    button.set_sensitive(row_action.disabled_reason.is_none());
    if let Some(reason) = &row_action.disabled_reason {
        button.set_tooltip_text(Some(reason));
    }
    if row_action.action.role == "destructive" {
        button.add_css_class("destructive-action");
    }
    let action = row_action.action.clone();
    button.connect_clicked(move |_| {
        model.borrow_mut().start_action(action.clone());
        refresh_window(&weak_window, model.clone());
    });
    button
}

fn muted_label(text: &str) -> gtk::Label {
    let label = gtk::Label::new(Some(text));
    label.set_xalign(0.0);
    label.set_wrap(true);
    label.add_css_class("gfc-muted");
    label
}

fn label(labels: &BTreeMap<String, String>, key: &str) -> String {
    labels.get(key).cloned().unwrap_or_else(|| key.to_string())
}
