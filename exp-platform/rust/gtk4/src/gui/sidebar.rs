use crate::app_model::GtkAppModel;
use crate::gui::refresh_window;
use crate::snapshot::UiSnapshot;
use gtk::glib;
use gtk::prelude::*;
use std::cell::RefCell;
use std::rc::Rc;

pub fn build(
    snapshot: &UiSnapshot,
    model: Rc<RefCell<GtkAppModel>>,
    weak_window: glib::WeakRef<adw::ApplicationWindow>,
) -> gtk::ScrolledWindow {
    let sidebar = gtk::Box::new(gtk::Orientation::Vertical, 12);
    sidebar.add_css_class("gfc-sidebar");
    sidebar.set_size_request(280, -1);

    let title = gtk::Label::new(Some(&snapshot.title));
    title.set_xalign(0.0);
    title.add_css_class("title-2");
    title.set_wrap(true);
    sidebar.append(&title);

    if !snapshot.summary.is_empty() {
        let info = gtk::Label::new(Some(&snapshot.summary));
        info.set_xalign(0.0);
        info.set_wrap(true);
        info.add_css_class("gfc-muted");
        sidebar.append(&info);
    }

    if !snapshot.setup_lines.is_empty() || !snapshot.setup_steps.is_empty() {
        let setup = gtk::Expander::new(Some(&label(snapshot, "app.setup.status.title")));
        setup.set_expanded(true);
        let setup_box = gtk::Box::new(gtk::Orientation::Vertical, 8);
        for line in &snapshot.setup_lines {
            setup_box.append(&muted_label(line));
        }
        for (index, step) in snapshot.setup_steps.iter().enumerate() {
            let button_label = if step.running {
                format!("⏳ {}", step.label)
            } else {
                format!(
                    "{}: {}",
                    label(snapshot, "app.setup.runButton.title"),
                    step.label
                )
            };
            let button = gtk::Button::with_label(&button_label);
            button.set_sensitive(!step.running);
            button.set_tooltip_text(Some(&step.command));
            let model = model.clone();
            let weak_window = weak_window.clone();
            button.connect_clicked(move |_| {
                model.borrow_mut().start_setup(index);
                refresh_window(&weak_window, model.clone());
            });
            setup_box.append(&button);
        }
        setup.set_child(Some(&setup_box));
        sidebar.append(&setup);
    }

    let options = gtk::Expander::new(Some(&label(snapshot, "app.standardOptions.title")));
    options.set_expanded(true);
    let options_box = gtk::Box::new(gtk::Orientation::Vertical, 8);
    options_box.append(&muted_label(&format!(
        "{}: {}",
        label(snapshot, "app.layoutDirection.label"),
        if snapshot.is_rtl { "rtl" } else { "ltr" }
    )));
    options_box.append(&muted_label(&format!(
        "{}: {}",
        label(snapshot, "app.terminal.textDirection.label"),
        snapshot.terminal_text_direction
    )));
    let workspace_button =
        gtk::Button::with_label(&label(snapshot, "app.workspace.openButton.title"));
    workspace_button.set_tooltip_text(Some(&snapshot.workspace_path));
    let workspace_model = model.clone();
    let workspace_weak = weak_window.clone();
    workspace_button.connect_clicked(move |_| {
        workspace_model.borrow_mut().open_workspace();
        refresh_window(&workspace_weak, workspace_model.clone());
    });
    options_box.append(&workspace_button);
    options.set_child(Some(&options_box));
    sidebar.append(&options);

    for (index, page) in snapshot.pages.iter().enumerate() {
        let button = gtk::Button::with_label(&page.title);
        if index == snapshot.selected_page {
            button.add_css_class("suggested-action");
        }
        let model = model.clone();
        let weak_window = weak_window.clone();
        button.connect_clicked(move |_| {
            model.borrow_mut().select_page(index);
            refresh_window(&weak_window, model.clone());
        });
        sidebar.append(&button);
    }

    gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .min_content_width(280)
        .child(&sidebar)
        .build()
}

fn muted_label(text: &str) -> gtk::Label {
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
