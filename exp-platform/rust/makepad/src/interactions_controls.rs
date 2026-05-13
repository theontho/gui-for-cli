use super::MakepadApp;
use makepad_widgets::*;

impl MakepadApp {
    pub(crate) fn handle_control_actions(&mut self, actions: &Actions) -> bool {
        let mut changed = false;
        if self.ui.button(id!(control_pick_0)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(0);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_1)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(1);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_2)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(2);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_3)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(3);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_4)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(4);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_5)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(5);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_6)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(6);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_7)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(7);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_8)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(8);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_9)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(9);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_10)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(10);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_11)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(11);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_12)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(12);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_13)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(13);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_14)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(14);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_15)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(15);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_16)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(16);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_17)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(17);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_18)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(18);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_19)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(19);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_20)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(20);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_21)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(21);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_22)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(22);
                changed = true;
            }
        }
        if self.ui.button(id!(control_pick_23)).clicked(actions) {
            if let Some(model) = &mut self.model {
                model.pick_control_path(23);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_0)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(0, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_1)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(1, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_2)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(2, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_3)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(3, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_4)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(4, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_5)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(5, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_6)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(6, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_7)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(7, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_8)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(8, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_9)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(9, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_10)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(10, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_11)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(11, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_12)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(12, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_13)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(13, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_14)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(14, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_15)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(15, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_16)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(16, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_17)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(17, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_18)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(18, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_19)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(19, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_20)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(20, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_21)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(21, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_22)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(22, value);
                changed = true;
            }
        }
        if let Some(value) = self.ui.text_input(id!(control_input_23)).changed(actions) {
            if let Some(model) = &mut self.model {
                model.update_field(23, value);
                changed = true;
            }
        }
        changed
    }
}
