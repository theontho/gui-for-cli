use super::MakepadApp;
use makepad_widgets::*;

impl MakepadApp {
    pub(crate) fn handle_command_actions(&mut self, actions: &Actions) -> bool {
        let mut changed = false;
        if self.ui.button(id!(action_0)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(0);
                changed = true;
            }
        }
        if self.ui.button(id!(action_1)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(1);
                changed = true;
            }
        }
        if self.ui.button(id!(action_2)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(2);
                changed = true;
            }
        }
        if self.ui.button(id!(action_3)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(3);
                changed = true;
            }
        }
        if self.ui.button(id!(action_4)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(4);
                changed = true;
            }
        }
        if self.ui.button(id!(action_5)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(5);
                changed = true;
            }
        }
        if self.ui.button(id!(action_6)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(6);
                changed = true;
            }
        }
        if self.ui.button(id!(action_7)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(7);
                changed = true;
            }
        }
        if self.ui.button(id!(action_8)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(8);
                changed = true;
            }
        }
        if self.ui.button(id!(action_9)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(9);
                changed = true;
            }
        }
        if self.ui.button(id!(action_10)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(10);
                changed = true;
            }
        }
        if self.ui.button(id!(action_11)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(11);
                changed = true;
            }
        }
        if self.ui.button(id!(action_12)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(12);
                changed = true;
            }
        }
        if self.ui.button(id!(action_13)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(13);
                changed = true;
            }
        }
        if self.ui.button(id!(action_14)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(14);
                changed = true;
            }
        }
        if self.ui.button(id!(action_15)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(15);
                changed = true;
            }
        }
        if self.ui.button(id!(action_16)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(16);
                changed = true;
            }
        }
        if self.ui.button(id!(action_17)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(17);
                changed = true;
            }
        }
        if self.ui.button(id!(action_18)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(18);
                changed = true;
            }
        }
        if self.ui.button(id!(action_19)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(19);
                changed = true;
            }
        }
        if self.ui.button(id!(action_20)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(20);
                changed = true;
            }
        }
        if self.ui.button(id!(action_21)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(21);
                changed = true;
            }
        }
        if self.ui.button(id!(action_22)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(22);
                changed = true;
            }
        }
        if self.ui.button(id!(action_23)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.start_action(23);
                changed = true;
            }
        }
        changed
    }
}
