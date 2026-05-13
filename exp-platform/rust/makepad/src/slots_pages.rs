use super::MakepadApp;
use makepad_widgets::*;

impl MakepadApp {
    pub(crate) fn set_page_slot(
        &self,
        cx: &mut Cx,
        index: usize,
        text: &str,
        visible: bool,
        selected: bool,
    ) {
        match index {
            0 => {
                self.ui.widget(id!(page_0)).set_visible(cx, visible);
                self.ui.widget(id!(page_0)).set_disabled(cx, selected);
                self.ui.button(id!(page_0)).set_text(cx, text);
            }
            1 => {
                self.ui.widget(id!(page_1)).set_visible(cx, visible);
                self.ui.widget(id!(page_1)).set_disabled(cx, selected);
                self.ui.button(id!(page_1)).set_text(cx, text);
            }
            2 => {
                self.ui.widget(id!(page_2)).set_visible(cx, visible);
                self.ui.widget(id!(page_2)).set_disabled(cx, selected);
                self.ui.button(id!(page_2)).set_text(cx, text);
            }
            3 => {
                self.ui.widget(id!(page_3)).set_visible(cx, visible);
                self.ui.widget(id!(page_3)).set_disabled(cx, selected);
                self.ui.button(id!(page_3)).set_text(cx, text);
            }
            4 => {
                self.ui.widget(id!(page_4)).set_visible(cx, visible);
                self.ui.widget(id!(page_4)).set_disabled(cx, selected);
                self.ui.button(id!(page_4)).set_text(cx, text);
            }
            5 => {
                self.ui.widget(id!(page_5)).set_visible(cx, visible);
                self.ui.widget(id!(page_5)).set_disabled(cx, selected);
                self.ui.button(id!(page_5)).set_text(cx, text);
            }
            6 => {
                self.ui.widget(id!(page_6)).set_visible(cx, visible);
                self.ui.widget(id!(page_6)).set_disabled(cx, selected);
                self.ui.button(id!(page_6)).set_text(cx, text);
            }
            7 => {
                self.ui.widget(id!(page_7)).set_visible(cx, visible);
                self.ui.widget(id!(page_7)).set_disabled(cx, selected);
                self.ui.button(id!(page_7)).set_text(cx, text);
            }
            8 => {
                self.ui.widget(id!(page_8)).set_visible(cx, visible);
                self.ui.widget(id!(page_8)).set_disabled(cx, selected);
                self.ui.button(id!(page_8)).set_text(cx, text);
            }
            9 => {
                self.ui.widget(id!(page_9)).set_visible(cx, visible);
                self.ui.widget(id!(page_9)).set_disabled(cx, selected);
                self.ui.button(id!(page_9)).set_text(cx, text);
            }
            10 => {
                self.ui.widget(id!(page_10)).set_visible(cx, visible);
                self.ui.widget(id!(page_10)).set_disabled(cx, selected);
                self.ui.button(id!(page_10)).set_text(cx, text);
            }
            11 => {
                self.ui.widget(id!(page_11)).set_visible(cx, visible);
                self.ui.widget(id!(page_11)).set_disabled(cx, selected);
                self.ui.button(id!(page_11)).set_text(cx, text);
            }
            12 => {
                self.ui.widget(id!(page_12)).set_visible(cx, visible);
                self.ui.widget(id!(page_12)).set_disabled(cx, selected);
                self.ui.button(id!(page_12)).set_text(cx, text);
            }
            13 => {
                self.ui.widget(id!(page_13)).set_visible(cx, visible);
                self.ui.widget(id!(page_13)).set_disabled(cx, selected);
                self.ui.button(id!(page_13)).set_text(cx, text);
            }
            14 => {
                self.ui.widget(id!(page_14)).set_visible(cx, visible);
                self.ui.widget(id!(page_14)).set_disabled(cx, selected);
                self.ui.button(id!(page_14)).set_text(cx, text);
            }
            15 => {
                self.ui.widget(id!(page_15)).set_visible(cx, visible);
                self.ui.widget(id!(page_15)).set_disabled(cx, selected);
                self.ui.button(id!(page_15)).set_text(cx, text);
            }
            _ => {
                debug_assert!(
                    false,
                    "set_page_slot index out of range: {index}; expected 0..16"
                );
            }
        }
    }

    pub(crate) fn set_setup_slot(
        &self,
        cx: &mut Cx,
        index: usize,
        title: &str,
        hint: &str,
        visible: bool,
        disabled: bool,
    ) {
        match index {
            0 => {
                self.ui.widget(id!(setup_0)).set_visible(cx, visible);
                self.ui.widget(id!(setup_0)).set_disabled(cx, disabled);
                self.ui.button(id!(setup_0)).set_text(cx, title);
                self.ui.widget(id!(setup_hint_0)).set_visible(cx, visible);
                self.ui.widget(id!(setup_hint_0)).set_text(cx, hint);
            }
            1 => {
                self.ui.widget(id!(setup_1)).set_visible(cx, visible);
                self.ui.widget(id!(setup_1)).set_disabled(cx, disabled);
                self.ui.button(id!(setup_1)).set_text(cx, title);
                self.ui.widget(id!(setup_hint_1)).set_visible(cx, visible);
                self.ui.widget(id!(setup_hint_1)).set_text(cx, hint);
            }
            2 => {
                self.ui.widget(id!(setup_2)).set_visible(cx, visible);
                self.ui.widget(id!(setup_2)).set_disabled(cx, disabled);
                self.ui.button(id!(setup_2)).set_text(cx, title);
                self.ui.widget(id!(setup_hint_2)).set_visible(cx, visible);
                self.ui.widget(id!(setup_hint_2)).set_text(cx, hint);
            }
            3 => {
                self.ui.widget(id!(setup_3)).set_visible(cx, visible);
                self.ui.widget(id!(setup_3)).set_disabled(cx, disabled);
                self.ui.button(id!(setup_3)).set_text(cx, title);
                self.ui.widget(id!(setup_hint_3)).set_visible(cx, visible);
                self.ui.widget(id!(setup_hint_3)).set_text(cx, hint);
            }
            4 => {
                self.ui.widget(id!(setup_4)).set_visible(cx, visible);
                self.ui.widget(id!(setup_4)).set_disabled(cx, disabled);
                self.ui.button(id!(setup_4)).set_text(cx, title);
                self.ui.widget(id!(setup_hint_4)).set_visible(cx, visible);
                self.ui.widget(id!(setup_hint_4)).set_text(cx, hint);
            }
            5 => {
                self.ui.widget(id!(setup_5)).set_visible(cx, visible);
                self.ui.widget(id!(setup_5)).set_disabled(cx, disabled);
                self.ui.button(id!(setup_5)).set_text(cx, title);
                self.ui.widget(id!(setup_hint_5)).set_visible(cx, visible);
                self.ui.widget(id!(setup_hint_5)).set_text(cx, hint);
            }
            6 => {
                self.ui.widget(id!(setup_6)).set_visible(cx, visible);
                self.ui.widget(id!(setup_6)).set_disabled(cx, disabled);
                self.ui.button(id!(setup_6)).set_text(cx, title);
                self.ui.widget(id!(setup_hint_6)).set_visible(cx, visible);
                self.ui.widget(id!(setup_hint_6)).set_text(cx, hint);
            }
            7 => {
                self.ui.widget(id!(setup_7)).set_visible(cx, visible);
                self.ui.widget(id!(setup_7)).set_disabled(cx, disabled);
                self.ui.button(id!(setup_7)).set_text(cx, title);
                self.ui.widget(id!(setup_hint_7)).set_visible(cx, visible);
                self.ui.widget(id!(setup_hint_7)).set_text(cx, hint);
            }
            _ => {
                debug_assert!(
                    false,
                    "set_setup_slot index out of range: {index}; expected 0..8"
                );
            }
        }
    }
}
