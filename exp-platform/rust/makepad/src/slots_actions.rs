use super::MakepadApp;
use crate::content::ActionSlot;
use makepad_widgets::*;

impl MakepadApp {
    pub(crate) fn set_action_slot(
        &self,
        cx: &mut Cx,
        index: usize,
        slot: &ActionSlot,
        visible: bool,
    ) {
        match index {
            0 => {
                self.ui.widget(id!(action_row_0)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_0))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_0)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_0))
                    .set_text(cx, &slot.preview);
            }
            1 => {
                self.ui.widget(id!(action_row_1)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_1))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_1)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_1))
                    .set_text(cx, &slot.preview);
            }
            2 => {
                self.ui.widget(id!(action_row_2)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_2))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_2)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_2))
                    .set_text(cx, &slot.preview);
            }
            3 => {
                self.ui.widget(id!(action_row_3)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_3))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_3)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_3))
                    .set_text(cx, &slot.preview);
            }
            4 => {
                self.ui.widget(id!(action_row_4)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_4))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_4)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_4))
                    .set_text(cx, &slot.preview);
            }
            5 => {
                self.ui.widget(id!(action_row_5)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_5))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_5)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_5))
                    .set_text(cx, &slot.preview);
            }
            6 => {
                self.ui.widget(id!(action_row_6)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_6))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_6)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_6))
                    .set_text(cx, &slot.preview);
            }
            7 => {
                self.ui.widget(id!(action_row_7)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_7))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_7)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_7))
                    .set_text(cx, &slot.preview);
            }
            8 => {
                self.ui.widget(id!(action_row_8)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_8))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_8)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_8))
                    .set_text(cx, &slot.preview);
            }
            9 => {
                self.ui.widget(id!(action_row_9)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_9))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_9)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_9))
                    .set_text(cx, &slot.preview);
            }
            10 => {
                self.ui.widget(id!(action_row_10)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_10))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_10)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_10))
                    .set_text(cx, &slot.preview);
            }
            11 => {
                self.ui.widget(id!(action_row_11)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_11))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_11)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_11))
                    .set_text(cx, &slot.preview);
            }
            12 => {
                self.ui.widget(id!(action_row_12)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_12))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_12)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_12))
                    .set_text(cx, &slot.preview);
            }
            13 => {
                self.ui.widget(id!(action_row_13)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_13))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_13)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_13))
                    .set_text(cx, &slot.preview);
            }
            14 => {
                self.ui.widget(id!(action_row_14)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_14))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_14)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_14))
                    .set_text(cx, &slot.preview);
            }
            15 => {
                self.ui.widget(id!(action_row_15)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_15))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_15)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_15))
                    .set_text(cx, &slot.preview);
            }
            16 => {
                self.ui.widget(id!(action_row_16)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_16))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_16)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_16))
                    .set_text(cx, &slot.preview);
            }
            17 => {
                self.ui.widget(id!(action_row_17)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_17))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_17)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_17))
                    .set_text(cx, &slot.preview);
            }
            18 => {
                self.ui.widget(id!(action_row_18)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_18))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_18)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_18))
                    .set_text(cx, &slot.preview);
            }
            19 => {
                self.ui.widget(id!(action_row_19)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_19))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_19)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_19))
                    .set_text(cx, &slot.preview);
            }
            20 => {
                self.ui.widget(id!(action_row_20)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_20))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_20)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_20))
                    .set_text(cx, &slot.preview);
            }
            21 => {
                self.ui.widget(id!(action_row_21)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_21))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_21)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_21))
                    .set_text(cx, &slot.preview);
            }
            22 => {
                self.ui.widget(id!(action_row_22)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_22))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_22)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_22))
                    .set_text(cx, &slot.preview);
            }
            23 => {
                self.ui.widget(id!(action_row_23)).set_visible(cx, visible);
                self.ui
                    .widget(id!(action_23))
                    .set_disabled(cx, slot.disabled);
                self.ui.button(id!(action_23)).set_text(cx, &slot.title);
                self.ui
                    .widget(id!(action_help_23))
                    .set_text(cx, &slot.preview);
            }
            _ => {}
        }
    }
}
