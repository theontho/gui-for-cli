mod controls;
mod page;
mod sidebar;
mod terminal;
mod window;

use crate::app_model::GtkAppModel;
use adw::prelude::*;
use anyhow::Result;
use gtk::glib;
use std::cell::RefCell;
use std::rc::Rc;

pub fn run(model: GtkAppModel) -> Result<()> {
    let application = adw::Application::builder()
        .application_id("dev.guiforcli.gtk4")
        .build();
    let model = Rc::new(RefCell::new(model));
    let shutdown_model = model.clone();
    application.connect_activate(move |application| {
        window::build(application, model.clone());
    });
    application.connect_shutdown(move |_| {
        shutdown_model.borrow_mut().cancel_all_running();
    });
    application.run();
    Ok(())
}

pub(crate) fn refresh_window(
    weak_window: &glib::WeakRef<adw::ApplicationWindow>,
    model: Rc<RefCell<GtkAppModel>>,
) {
    if let Some(window) = weak_window.upgrade() {
        window::render(&window, model);
    }
}
