use crate::args::parse_args;
use crate::content::{
    ActionSlot, ControlSlot, MAX_ACTIONS, MAX_CONTROLS, MAX_PAGES, MAX_SETUP, MAX_TERMINALS,
    PageSnapshot, page_snapshot, setup_button_title, setup_text, status_hint, terminal_output,
    terminal_tab_label,
};
use crate::model::MakepadModel;
use crate::terminal::TerminalStatus;
use makepad_widgets::*;

include!("design.rs");

#[path = "interactions.rs"]
mod interactions;
#[path = "interactions_actions.rs"]
mod interactions_actions;
#[path = "interactions_controls.rs"]
mod interactions_controls;
#[path = "interactions_pages.rs"]
mod interactions_pages;
#[path = "interactions_terminal.rs"]
mod interactions_terminal;
#[path = "slots_actions.rs"]
mod slots_actions;
#[path = "slots_controls.rs"]
mod slots_controls;
#[path = "slots_pages.rs"]
mod slots_pages;
#[path = "slots_terminal.rs"]
mod slots_terminal;

app_main!(MakepadApp);

#[derive(Live, LiveHook)]
pub struct MakepadApp {
    #[live]
    ui: WidgetRef,
    #[rust]
    model: Option<MakepadModel>,
    #[rust]
    next_frame: NextFrame,
}

impl LiveRegister for MakepadApp {
    fn live_register(cx: &mut Cx) {
        crate::makepad_widgets::live_design(cx);
    }
}

impl MatchEvent for MakepadApp {
    fn handle_startup(&mut self, cx: &mut Cx) {
        match parse_args().and_then(MakepadModel::load) {
            Ok(mut model) => {
                model.print_benchmark_if_requested();
                self.model = Some(model);
                self.refresh(cx);
                self.next_frame = cx.new_next_frame();
            }
            Err(error) => {
                self.ui
                    .widget(id!(title))
                    .set_text(cx, "GUI for CLI Makepad");
                self.ui
                    .widget(id!(summary))
                    .set_text(cx, &format!("Could not load bundle: {error:#}"));
            }
        }
    }

    fn handle_actions(&mut self, cx: &mut Cx, actions: &Actions) {
        if self.handle_makepad_actions(actions) {
            self.refresh(cx);
            self.next_frame = cx.new_next_frame();
        }
    }
}

impl AppMain for MakepadApp {
    fn handle_event(&mut self, cx: &mut Cx, event: &Event) {
        if matches!(event, Event::WindowCloseRequested(_)) {
            if let Some(model) = &mut self.model {
                model.cancel_all_running();
            }
        }
        if let Event::NextFrame(event) = event {
            if event.set.contains(&self.next_frame) {
                let mut keep_polling = false;
                if let Some(model) = &mut self.model {
                    keep_polling = has_running_terminal(model);
                    if model.poll_finished_commands() {
                        self.refresh(cx);
                    }
                }
                if keep_polling {
                    self.next_frame = cx.new_next_frame();
                }
            }
        }
        self.match_event(cx, event);
        self.ui.handle_event(cx, event, &mut Scope::empty());
    }
}

impl MakepadApp {
    pub(crate) fn refresh(&mut self, cx: &mut Cx) {
        let Some(model) = &self.model else {
            return;
        };
        let title = model.title.clone();
        let summary = model.summary.clone();
        let setup_text_value = setup_text(model);
        let terminal_visible = model.terminal_visible;
        let setup_slots = (0..MAX_SETUP)
            .map(|index| setup_button_title(model, index))
            .collect::<Vec<_>>();
        let page_slots = (0..MAX_PAGES)
            .map(|index| {
                model.pages.get(index).map(|page| {
                    let selected = index == model.selected_page;
                    let title = if selected {
                        format!("▶ {}", page.title)
                    } else {
                        page.title.clone()
                    };
                    (title, selected)
                })
            })
            .collect::<Vec<_>>();
        let snapshot = if let Some(model) = &mut self.model {
            page_snapshot(model)
        } else {
            PageSnapshot::default()
        };

        self.ui.widget(id!(title)).set_text(cx, &title);
        self.ui.widget(id!(summary)).set_text(cx, &summary);
        self.ui
            .widget(id!(setup_text))
            .set_text(cx, &setup_text_value);
        self.ui.widget(id!(toggle_terminal)).set_text(
            cx,
            if terminal_visible {
                "Hide Terminal"
            } else {
                "Show Terminal"
            },
        );
        self.ui
            .widget(id!(terminal))
            .set_visible(cx, terminal_visible);
        for (index, slot) in setup_slots.into_iter().enumerate() {
            if let Some((title, hint, disabled)) = slot {
                self.set_setup_slot(cx, index, &title, &hint, true, disabled);
            } else {
                self.set_setup_slot(cx, index, "", "", false, true);
            }
        }
        for (index, slot) in page_slots.into_iter().enumerate() {
            if let Some((title, selected)) = slot {
                self.set_page_slot(cx, index, &title, true, selected);
            } else {
                self.set_page_slot(cx, index, "", false, false);
            }
        }
        self.apply_page_snapshot(cx, &snapshot);
        self.apply_terminal(cx);
        self.ui.redraw(cx);
    }

    fn apply_page_snapshot(&self, cx: &mut Cx, snapshot: &PageSnapshot) {
        self.ui
            .widget(id!(page_title))
            .set_text(cx, &snapshot.title);
        self.ui
            .widget(id!(page_summary))
            .set_text(cx, &snapshot.summary);
        self.ui.widget(id!(page_body)).set_text(cx, &snapshot.body);
        for index in 0..MAX_CONTROLS {
            if let Some(slot) = snapshot.controls.get(index) {
                self.set_control_slot(cx, index, slot, true);
            } else {
                self.set_control_slot(cx, index, &ControlSlot::default(), false);
            }
        }
        for index in 0..MAX_ACTIONS {
            if let Some(slot) = snapshot.actions.get(index) {
                self.set_action_slot(cx, index, slot, true);
            } else {
                self.set_action_slot(cx, index, &ActionSlot::default(), false);
            }
        }
    }

    fn apply_terminal(&self, cx: &mut Cx) {
        let Some(model) = &self.model else {
            return;
        };
        for index in 0..MAX_TERMINALS {
            if let Some(entry) = model.terminal.entries().get(index) {
                self.set_terminal_slot(cx, index, &terminal_tab_label(entry), true);
            } else {
                self.set_terminal_slot(cx, index, "", false);
            }
        }
        if let Some(entry) = model.terminal.selected_entry() {
            self.ui
                .widget(id!(terminal_hint))
                .set_text(cx, &status_hint(entry));
        }
        self.ui
            .widget(id!(terminal_output))
            .set_text(cx, &terminal_output(model));
    }
}

fn has_running_terminal(model: &MakepadModel) -> bool {
    model
        .terminal
        .entries()
        .iter()
        .any(|entry| entry.status == TerminalStatus::Running)
}
