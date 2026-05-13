use super::MakepadApp;
use makepad_widgets::*;

impl MakepadApp {
    pub(crate) fn handle_makepad_actions(&mut self, actions: &Actions) -> bool {
        let mut changed = self.handle_page_setup_actions(actions);
        changed |= self.handle_control_actions(actions);
        changed |= self.handle_command_actions(actions);
        changed |= self.handle_terminal_actions(actions);
        if self.ui.button(id!(open_workspace)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.open_workspace();
                changed = true;
            }
        }
        if self.ui.button(id!(toggle_terminal)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.terminal_visible = !model.terminal_visible;
                changed = true;
            }
        }
        changed
    }
}
