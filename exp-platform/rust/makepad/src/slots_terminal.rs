use super::MakepadApp;
use makepad_widgets::*;

impl MakepadApp {
    pub(crate) fn set_terminal_slot(&self, cx: &mut Cx, index: usize, text: &str, visible: bool) {
        match index {
            0 => {
                self.ui.widget(id!(tab_0)).set_visible(cx, visible);
                self.ui.button(id!(tab_0)).set_text(cx, text);
            }
            1 => {
                self.ui.widget(id!(tab_1)).set_visible(cx, visible);
                self.ui.button(id!(tab_1)).set_text(cx, text);
            }
            2 => {
                self.ui.widget(id!(tab_2)).set_visible(cx, visible);
                self.ui.button(id!(tab_2)).set_text(cx, text);
            }
            3 => {
                self.ui.widget(id!(tab_3)).set_visible(cx, visible);
                self.ui.button(id!(tab_3)).set_text(cx, text);
            }
            4 => {
                self.ui.widget(id!(tab_4)).set_visible(cx, visible);
                self.ui.button(id!(tab_4)).set_text(cx, text);
            }
            5 => {
                self.ui.widget(id!(tab_5)).set_visible(cx, visible);
                self.ui.button(id!(tab_5)).set_text(cx, text);
            }
            6 => {
                self.ui.widget(id!(tab_6)).set_visible(cx, visible);
                self.ui.button(id!(tab_6)).set_text(cx, text);
            }
            7 => {
                self.ui.widget(id!(tab_7)).set_visible(cx, visible);
                self.ui.button(id!(tab_7)).set_text(cx, text);
            }
            8 => {
                self.ui.widget(id!(tab_8)).set_visible(cx, visible);
                self.ui.button(id!(tab_8)).set_text(cx, text);
            }
            9 => {
                self.ui.widget(id!(tab_9)).set_visible(cx, visible);
                self.ui.button(id!(tab_9)).set_text(cx, text);
            }
            10 => {
                self.ui.widget(id!(tab_10)).set_visible(cx, visible);
                self.ui.button(id!(tab_10)).set_text(cx, text);
            }
            11 => {
                self.ui.widget(id!(tab_11)).set_visible(cx, visible);
                self.ui.button(id!(tab_11)).set_text(cx, text);
            }
            _ => {
                debug_assert!(
                    false,
                    "set_terminal_slot index out of range: {index}; expected 0..12"
                );
            }
        }
    }
}
