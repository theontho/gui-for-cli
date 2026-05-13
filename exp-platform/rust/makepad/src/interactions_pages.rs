use super::MakepadApp;
use makepad_widgets::*;

impl MakepadApp {
    pub(crate) fn handle_page_setup_actions(&mut self, actions: &Actions) -> bool {
        let mut changed = false;
        if self.ui.button(id!(page_0)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(0);
                changed = true;
            }
        }
        if self.ui.button(id!(page_1)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(1);
                changed = true;
            }
        }
        if self.ui.button(id!(page_2)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(2);
                changed = true;
            }
        }
        if self.ui.button(id!(page_3)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(3);
                changed = true;
            }
        }
        if self.ui.button(id!(page_4)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(4);
                changed = true;
            }
        }
        if self.ui.button(id!(page_5)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(5);
                changed = true;
            }
        }
        if self.ui.button(id!(page_6)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(6);
                changed = true;
            }
        }
        if self.ui.button(id!(page_7)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(7);
                changed = true;
            }
        }
        if self.ui.button(id!(page_8)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(8);
                changed = true;
            }
        }
        if self.ui.button(id!(page_9)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(9);
                changed = true;
            }
        }
        if self.ui.button(id!(page_10)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(10);
                changed = true;
            }
        }
        if self.ui.button(id!(page_11)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(11);
                changed = true;
            }
        }
        if self.ui.button(id!(page_12)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(12);
                changed = true;
            }
        }
        if self.ui.button(id!(page_13)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(13);
                changed = true;
            }
        }
        if self.ui.button(id!(page_14)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(14);
                changed = true;
            }
        }
        if self.ui.button(id!(page_15)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.select_page(15);
                changed = true;
            }
        }
        if self.ui.button(id!(setup_0)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_setup(0);
                changed = true;
            }
        }
        if self.ui.button(id!(setup_1)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_setup(1);
                changed = true;
            }
        }
        if self.ui.button(id!(setup_2)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_setup(2);
                changed = true;
            }
        }
        if self.ui.button(id!(setup_3)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_setup(3);
                changed = true;
            }
        }
        if self.ui.button(id!(setup_4)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_setup(4);
                changed = true;
            }
        }
        if self.ui.button(id!(setup_5)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_setup(5);
                changed = true;
            }
        }
        if self.ui.button(id!(setup_6)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_setup(6);
                changed = true;
            }
        }
        if self.ui.button(id!(setup_7)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_setup(7);
                changed = true;
            }
        }
        changed
    }
}
