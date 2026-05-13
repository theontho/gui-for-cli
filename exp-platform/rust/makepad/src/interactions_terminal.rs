use super::MakepadApp;
use makepad_widgets::*;

impl MakepadApp {
    pub(crate) fn handle_terminal_actions(&mut self, actions: &Actions) -> bool {
        let mut changed = false;
        if self.ui.button(id!(tab_0)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.terminal.select(0);
                model.handle_terminal_tab(0);
                changed = true;
            }
        }
        if self.ui.button(id!(tab_1)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.terminal.select(1);
                model.handle_terminal_tab(1);
                changed = true;
            }
        }
        if self.ui.button(id!(tab_2)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.terminal.select(2);
                model.handle_terminal_tab(2);
                changed = true;
            }
        }
        if self.ui.button(id!(tab_3)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.terminal.select(3);
                model.handle_terminal_tab(3);
                changed = true;
            }
        }
        if self.ui.button(id!(tab_4)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.terminal.select(4);
                model.handle_terminal_tab(4);
                changed = true;
            }
        }
        if self.ui.button(id!(tab_5)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.terminal.select(5);
                model.handle_terminal_tab(5);
                changed = true;
            }
        }
        if self.ui.button(id!(tab_6)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.terminal.select(6);
                model.handle_terminal_tab(6);
                changed = true;
            }
        }
        if self.ui.button(id!(tab_7)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.terminal.select(7);
                model.handle_terminal_tab(7);
                changed = true;
            }
        }
        if self.ui.button(id!(tab_8)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.terminal.select(8);
                model.handle_terminal_tab(8);
                changed = true;
            }
        }
        if self.ui.button(id!(tab_9)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.terminal.select(9);
                model.handle_terminal_tab(9);
                changed = true;
            }
        }
        if self.ui.button(id!(tab_10)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.terminal.select(10);
                model.handle_terminal_tab(10);
                changed = true;
            }
        }
        if self.ui.button(id!(tab_11)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.terminal.select(11);
                model.handle_terminal_tab(11);
                changed = true;
            }
        }
        changed
    }
}
