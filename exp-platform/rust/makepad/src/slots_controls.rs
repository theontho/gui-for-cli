use super::MakepadApp;
use crate::content::ControlSlot;
use makepad_widgets::*;

impl MakepadApp {
    pub(crate) fn set_control_slot(
        &self,
        cx: &mut Cx,
        index: usize,
        slot: &ControlSlot,
        visible: bool,
    ) {
        match index {
            0 => {
                self.ui.widget(id!(control_row_0)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_0))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_0))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_0))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_0))
                    .set_visible(cx, visible && slot.show_picker);
            }
            1 => {
                self.ui.widget(id!(control_row_1)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_1))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_1))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_1))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_1))
                    .set_visible(cx, visible && slot.show_picker);
            }
            2 => {
                self.ui.widget(id!(control_row_2)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_2))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_2))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_2))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_2))
                    .set_visible(cx, visible && slot.show_picker);
            }
            3 => {
                self.ui.widget(id!(control_row_3)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_3))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_3))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_3))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_3))
                    .set_visible(cx, visible && slot.show_picker);
            }
            4 => {
                self.ui.widget(id!(control_row_4)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_4))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_4))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_4))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_4))
                    .set_visible(cx, visible && slot.show_picker);
            }
            5 => {
                self.ui.widget(id!(control_row_5)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_5))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_5))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_5))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_5))
                    .set_visible(cx, visible && slot.show_picker);
            }
            6 => {
                self.ui.widget(id!(control_row_6)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_6))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_6))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_6))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_6))
                    .set_visible(cx, visible && slot.show_picker);
            }
            7 => {
                self.ui.widget(id!(control_row_7)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_7))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_7))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_7))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_7))
                    .set_visible(cx, visible && slot.show_picker);
            }
            8 => {
                self.ui.widget(id!(control_row_8)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_8))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_8))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_8))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_8))
                    .set_visible(cx, visible && slot.show_picker);
            }
            9 => {
                self.ui.widget(id!(control_row_9)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_9))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_9))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_9))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_9))
                    .set_visible(cx, visible && slot.show_picker);
            }
            10 => {
                self.ui.widget(id!(control_row_10)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_10))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_10))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_10))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_10))
                    .set_visible(cx, visible && slot.show_picker);
            }
            11 => {
                self.ui.widget(id!(control_row_11)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_11))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_11))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_11))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_11))
                    .set_visible(cx, visible && slot.show_picker);
            }
            12 => {
                self.ui.widget(id!(control_row_12)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_12))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_12))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_12))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_12))
                    .set_visible(cx, visible && slot.show_picker);
            }
            13 => {
                self.ui.widget(id!(control_row_13)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_13))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_13))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_13))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_13))
                    .set_visible(cx, visible && slot.show_picker);
            }
            14 => {
                self.ui.widget(id!(control_row_14)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_14))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_14))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_14))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_14))
                    .set_visible(cx, visible && slot.show_picker);
            }
            15 => {
                self.ui.widget(id!(control_row_15)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_15))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_15))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_15))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_15))
                    .set_visible(cx, visible && slot.show_picker);
            }
            16 => {
                self.ui.widget(id!(control_row_16)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_16))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_16))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_16))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_16))
                    .set_visible(cx, visible && slot.show_picker);
            }
            17 => {
                self.ui.widget(id!(control_row_17)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_17))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_17))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_17))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_17))
                    .set_visible(cx, visible && slot.show_picker);
            }
            18 => {
                self.ui.widget(id!(control_row_18)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_18))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_18))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_18))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_18))
                    .set_visible(cx, visible && slot.show_picker);
            }
            19 => {
                self.ui.widget(id!(control_row_19)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_19))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_19))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_19))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_19))
                    .set_visible(cx, visible && slot.show_picker);
            }
            20 => {
                self.ui.widget(id!(control_row_20)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_20))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_20))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_20))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_20))
                    .set_visible(cx, visible && slot.show_picker);
            }
            21 => {
                self.ui.widget(id!(control_row_21)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_21))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_21))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_21))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_21))
                    .set_visible(cx, visible && slot.show_picker);
            }
            22 => {
                self.ui.widget(id!(control_row_22)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_22))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_22))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_22))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_22))
                    .set_visible(cx, visible && slot.show_picker);
            }
            23 => {
                self.ui.widget(id!(control_row_23)).set_visible(cx, visible);
                self.ui
                    .widget(id!(control_label_23))
                    .set_text(cx, &slot.label);
                self.ui
                    .widget(id!(control_input_23))
                    .set_text(cx, &slot.value);
                self.ui
                    .widget(id!(control_help_23))
                    .set_text(cx, &slot.helper);
                self.ui
                    .widget(id!(control_pick_23))
                    .set_visible(cx, visible && slot.show_picker);
            }
            _ => {}
        }
    }
}
