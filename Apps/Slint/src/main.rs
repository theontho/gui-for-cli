#[path = "../../RustShared/src/args.rs"]
mod args;
#[path = "../../RustShared/src/bundle.rs"]
mod bundle;
#[path = "../../RustShared/src/control_text.rs"]
mod control_text;
#[path = "../../RustShared/src/data_source_cache.rs"]
mod data_source_cache;
#[path = "../../RustShared/src/execution.rs"]
mod execution;
#[path = "../../RustShared/src/exit_codes.rs"]
mod exit_codes;
#[path = "../../RustShared/src/path_picker.rs"]
mod path_picker;
#[path = "../../RustShared/src/row_actions.rs"]
mod row_actions;
#[path = "../../RustShared/src/state.rs"]
mod state;
#[path = "../../RustShared/src/terminal.rs"]
mod terminal;
#[path = "../../RustShared/src/workspace.rs"]
mod workspace;

use anyhow::{Context, Result, anyhow};
use args::{configure_default_renderer, parse_args};
use bundle::{PageView, load_bundle};
use control_text::{control_options, data_source_values, setup_command_preview};
use execution::{
    action_preview, action_unavailable_reason, cancel_running_process, confirmation_prompt,
    is_action_visible, prepare_action_command, prepare_setup_command, run_prepared_command_tracked,
    running_process_registry,
};
use path_picker::pick_path;
use row_actions::data_source_row_actions;
use slint::{ComponentHandle, ModelRc, SharedString, VecModel};
use state::{
    PersistedState, control_persists_field_value, initial_field_values, load_state,
    persist_field_value, persist_selected_page, save_config_value, save_state, selected_page_index,
};
use std::cell::RefCell;
use std::collections::BTreeMap;
use std::path::Path;
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Instant;
use terminal::{TerminalAction, TerminalStatus, TerminalStore, status_label};
use workspace::prepare_bundle_workspace;

slint::slint! {
    import { Button, CheckBox, LineEdit, ScrollView } from "std-widgets.slint";

    export struct PageTab {
        title: string,
    }

    export struct PageAction {
        title: string,
        command: string,
        enabled: bool,
    }

    export struct SetupAction {
        title: string,
        command: string,
    }

    export struct PageControl {
        id: string,
        label: string,
        kind: string,
        value: string,
        placeholder: string,
        helper: string,
        options: string,
    }

    export struct TerminalTab {
        title: string,
        status: string,
        action: string,
    }

    export component AppWindow inherits Window {
        in property <string> window-title;
        in property <string> bundle-summary;
        in property <string> setup-summary;
        in property <string> page-title;
        in property <string> page-summary;
        in property <string> page-body;
        in property <string> terminal-output;
        in property <bool> terminal-visible: true;
        in property <[PageTab]> pages;
        in property <[PageAction]> actions;
        in property <[SetupAction]> setup-actions;
        in property <[PageControl]> controls;
        in property <[TerminalTab]> terminal-tabs;
        callback page-selected(int);
        callback action-selected(int);
        callback setup-selected(int);
        callback terminal-selected(int);
        callback terminal-action(int);
        callback terminal-toggle();
        callback control-edited(string, string);
        callback path-picked(string, string, string);

        title: root.window-title;
        preferred-width: 1120px;
        preferred-height: 720px;
        min-width: 720px;
        min-height: 480px;
        background: #f6f7fb;

        HorizontalLayout {
            padding: 16px;
            spacing: 16px;

            Rectangle {
                width: 260px;
                background: #ffffff;
                border-color: #d7dbe7;
                border-radius: 12px;

                VerticalLayout {
                    padding: 14px;
                    spacing: 10px;

                    Text {
                        text: root.window-title;
                        font-size: 22px;
                        font-weight: 700;
                        color: #1c2333;
                    }

                     Text {
                         text: root.bundle-summary;
                         wrap: word-wrap;
                         color: #566070;
                     }

                     Text {
                          text: root.setup-summary;
                          wrap: word-wrap;
                          color: #566070;
                      }

                       for setup[index] in root.setup-actions : Rectangle {
                           height: 54px;

                           VerticalLayout {
                               spacing: 4px;

                               Button {
                                   text: setup.title;
                                   clicked => {
                                       root.setup-selected(index);
                                   }
                               }

                               Text {
                                   text: setup.command;
                                   wrap: word-wrap;
                                   color: #566070;
                                   font-size: 11px;
                               }
                           }
                       }

                    Rectangle { height: 1px; background: #e4e7ef; }

                    ScrollView {
                        viewport-width: 232px;

                        VerticalLayout {
                            spacing: 8px;

                            for page[index] in root.pages : Button {
                                text: page.title;
                                clicked => {
                                    root.page-selected(index);
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                min-width: 0px;
                horizontal-stretch: 1;
                background: #ffffff;
                border-color: #d7dbe7;
                border-radius: 12px;

                VerticalLayout {
                    padding: 18px;
                    spacing: 12px;

                    Text {
                        text: root.page-title;
                        font-size: 26px;
                        font-weight: 700;
                        color: #1c2333;
                    }

                    Text {
                        text: root.page-summary;
                        wrap: word-wrap;
                        color: #566070;
                    }

                    Rectangle { height: 1px; background: #e4e7ef; }

                     ScrollView {
                         min-width: 0px;
                         horizontal-stretch: 1;

                         VerticalLayout {
                             min-width: 0px;
                             spacing: 12px;

                               Text {
                                  min-width: 0px;
                                  horizontal-stretch: 1;
                                  text: root.page-body;
                                  wrap: word-wrap;
                                  color: #263044;
                                  font-size: 15px;
                              }

                               for control in root.controls : Rectangle {
                                   min-width: 0px;
                                   horizontal-stretch: 1;
                                   height: control.kind == "libraryList" ? 280px : control.kind == "infoGrid" ? 180px : 142px;
                                  background: #f8f9fc;
                                  border-color: #e1e5ef;
                                  border-radius: 10px;

                                  VerticalLayout {
                                      padding: 10px;
                                      spacing: 6px;

                                      Text {
                                          text: control.label;
                                          font-size: 15px;
                                          font-weight: 700;
                                          color: #1c2333;
                                      }

                                      if control.kind == "text" || control.kind == "path" || control.kind == "dropdown" || control.kind == "checkboxGroup" : LineEdit {
                                          text: control.value;
                                          placeholder-text: control.placeholder;
                                          edited(value) => {
                                              root.control-edited(control.id, value);
                                          }
                                      }

                                      if control.kind == "path" : Button {
                                          text: "Browse…";
                                          clicked => {
                                              root.path-picked(control.id, control.label, control.value);
                                          }
                                      }

                                      if control.kind == "toggle" : CheckBox {
                                          text: "Enabled";
                                          checked: control.value == "true";
                                          toggled => {
                                              root.control-edited(control.id, self.checked ? "true" : "false");
                                          }
                                      }

                                       if control.kind != "text" && control.kind != "path" && control.kind != "dropdown" && control.kind != "checkboxGroup" && control.kind != "toggle" : Text {
                                           min-width: 0px;
                                           horizontal-stretch: 1;
                                            text: control.options == "" ? control.value : control.options;
                                           wrap: word-wrap;
                                           color: #566070;
                                      }

                                       if control.kind == "dropdown" || control.kind == "checkboxGroup" : Text {
                                           min-width: 0px;
                                           horizontal-stretch: 1;
                                           text: control.options;
                                          wrap: word-wrap;
                                          color: #566070;
                                          font-size: 12px;
                                      }

                                       Text {
                                           min-width: 0px;
                                           horizontal-stretch: 1;
                                           text: control.helper;
                                          wrap: word-wrap;
                                          color: #566070;
                                          font-size: 12px;
                                      }
                                  }
                              }

                              Rectangle { height: 1px; background: #e4e7ef; }

                             Text {
                                 text: "Actions";
                                 font-size: 18px;
                                 font-weight: 700;
                                 color: #1c2333;
                             }

                               for action[index] in root.actions : Rectangle {
                                   min-width: 0px;
                                   horizontal-stretch: 1;
                                   height: 64px;

                                   VerticalLayout {
                                       spacing: 4px;

                                       Button {
                                           text: action.title;
                                           enabled: action.enabled;
                                           clicked => {
                                               root.action-selected(index);
                                           }
                                       }

                                       Text {
                                           min-width: 0px;
                                           horizontal-stretch: 1;
                                           text: action.command;
                                           wrap: word-wrap;
                                           color: action.enabled ? #566070 : #8a5160;
                                           font-size: 11px;
                                       }
                                   }
                               }

                          }
                      }

                      Rectangle { height: 1px; background: #e4e7ef; }

                      if root.terminal-visible : Rectangle {
                          min-width: 0px;
                          horizontal-stretch: 1;
                          height: 180px;
                          background: #f8f9fc;
                          border-color: #e1e5ef;
                          border-radius: 10px;

                          VerticalLayout {
                              padding: 8px;
                              spacing: 6px;

                              HorizontalLayout {
                                  spacing: 6px;
                                  for tab[index] in root.terminal-tabs : HorizontalLayout {
                                      spacing: 2px;

                                      Button {
                                          text: tab.title + " [" + tab.status + "]";
                                          clicked => {
                                              root.terminal-selected(index);
                                          }
                                      }

                                      if tab.action != "" : Button {
                                          text: tab.action;
                                          clicked => {
                                              root.terminal-action(index);
                                          }
                                      }
                                  }

                                  Rectangle { horizontal-stretch: 1; }

                                  Button {
                                      text: "Hide terminal";
                                      clicked => {
                                          root.terminal-toggle();
                                      }
                                  }
                              }

                              ScrollView {
                                  min-width: 0px;
                                  horizontal-stretch: 1;
                                  vertical-stretch: 1;

                                  Text {
                                      min-width: 0px;
                                      horizontal-stretch: 1;
                                      text: root.terminal-output;
                                      wrap: word-wrap;
                                      color: #263044;
                                      font-size: 13px;
                                  }
                              }
                          }
                      }

                      if !root.terminal-visible : HorizontalLayout {
                          Rectangle { horizontal-stretch: 1; }

                          Button {
                              text: "Show terminal";
                              clicked => {
                                  root.terminal-toggle();
                              }
                          }
                      }
                  }
             }
         }
    }
}

fn main() {
    if let Err(error) = run() {
        eprintln!("gui-for-cli-slint: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let started = Instant::now();
    let args = parse_args()?;
    let (bundle_root, workspace_messages) = prepare_bundle_workspace(&args.bundle)?;
    let bundle = load_bundle(&bundle_root, &args.repo_root, &args.locale)?;
    let loaded_ms = started.elapsed().as_secs_f64() * 1000.0;
    configure_default_renderer();

    let mut startup_messages = workspace_messages;
    let persisted = match load_state(&bundle_root) {
        Ok(state) => state,
        Err(error) => {
            startup_messages.push(format!("Could not load Slint state: {error:#}"));
            PersistedState::default()
        }
    };
    let selected_index = selected_page_index(&bundle.pages, &persisted);
    let field_values = Rc::new(RefCell::new(initial_field_values(
        &bundle.pages,
        &persisted,
    )));
    let persisted_state = Rc::new(RefCell::new(persisted));
    let data_source_cache = Rc::new(RefCell::new(BTreeMap::new()));
    let terminal_store = Arc::new(Mutex::new(TerminalStore::new()));
    let running_processes = running_process_registry();
    if !startup_messages.is_empty() {
        terminal_store
            .lock()
            .expect("terminal store")
            .replace_main(startup_messages.join("\n"));
    }
    let page_tabs = bundle
        .pages
        .iter()
        .map(|page| PageTab {
            title: page.title.as_str().into(),
        })
        .collect::<Vec<_>>();
    let setup_actions = bundle
        .setup_steps
        .iter()
        .map(|step| SetupAction {
            title: step.label.as_str().into(),
            command: setup_command_preview(step).as_str().into(),
        })
        .collect::<Vec<_>>();
    let setup_steps = Rc::new(bundle.setup_steps);
    let control_count = bundle.control_count;
    let action_count = bundle.action_count;
    let data_source_count = bundle.data_source_count;
    let exit_code_reference = Rc::new(bundle.exit_code_reference.clone());
    let bundle_root = Rc::new(bundle_root);
    let pages = Rc::new(bundle.pages);
    let first_page = pages
        .get(selected_index)
        .or_else(|| pages.first())
        .ok_or_else(|| anyhow!("bundle has no pages"))?;

    let ui = AppWindow::new().context("create Slint window")?;
    ui.set_window_title(bundle.title.as_str().into());
    ui.set_bundle_summary(bundle.summary.as_str().into());
    ui.set_setup_summary(bundle.setup_lines.join("\n").as_str().into());
    update_terminal(&ui, &terminal_store.lock().expect("terminal store"));
    ui.set_pages(ModelRc::new(Rc::new(VecModel::from(page_tabs))));
    ui.set_setup_actions(ModelRc::new(Rc::new(VecModel::from(setup_actions))));
    set_page(
        &ui,
        first_page,
        &field_values.borrow(),
        &mut data_source_cache.borrow_mut(),
        &bundle_root,
    );

    let ui_weak = ui.as_weak();
    let pages_for_callback = pages.clone();
    let selected_page = Rc::new(RefCell::new(selected_index));
    let selected_for_page = selected_page.clone();
    let field_values_for_page = field_values.clone();
    let data_source_cache_for_page = data_source_cache.clone();
    let bundle_root_for_page = bundle_root.clone();
    let persisted_for_page = persisted_state.clone();
    let terminal_for_page = terminal_store.clone();
    ui.on_page_selected(move |index| {
        if let Some(ui) = ui_weak.upgrade() {
            if let Some(page) = pages_for_callback.get(index.max(0) as usize) {
                *selected_for_page.borrow_mut() = index.max(0) as usize;
                persist_selected_page(&mut persisted_for_page.borrow_mut(), page);
                if let Err(error) = save_state(&persisted_for_page.borrow(), &bundle_root_for_page)
                {
                    terminal_for_page
                        .lock()
                        .expect("terminal store")
                        .push_result("State", format!("Could not save selected page: {error:#}"));
                    update_terminal(&ui, &terminal_for_page.lock().expect("terminal store"));
                }
                set_page(
                    &ui,
                    page,
                    &field_values_for_page.borrow(),
                    &mut data_source_cache_for_page.borrow_mut(),
                    &bundle_root_for_page,
                );
            }
        }
    });
    let ui_weak = ui.as_weak();
    let field_values_for_controls = field_values.clone();
    let pages_for_controls = pages.clone();
    let selected_for_controls = selected_page.clone();
    let data_source_cache_for_controls = data_source_cache.clone();
    let bundle_root_for_controls = bundle_root.clone();
    let persisted_for_controls = persisted_state.clone();
    let terminal_for_controls = terminal_store.clone();
    ui.on_control_edited(move |id, value| {
        field_values_for_controls
            .borrow_mut()
            .insert(id.to_string(), value.to_string());
        if let Some(ui) = ui_weak.upgrade() {
            let selected = *selected_for_controls.borrow();
            if let Some(page) = pages_for_controls.get(selected) {
                if let Some(control) = control_for_id(page, &id) {
                    if control_persists_field_value(control) {
                        persist_field_value(&mut persisted_for_controls.borrow_mut(), &id, &value);
                        if let Err(error) =
                            save_state(&persisted_for_controls.borrow(), &bundle_root_for_controls)
                        {
                            terminal_for_controls
                                .lock()
                                .expect("terminal store")
                                .push_result(
                                    "State",
                                    format!("Could not save field value: {error:#}"),
                                );
                        }
                    }
                    if let Err(error) = save_config_value(control, &value) {
                        terminal_for_controls
                            .lock()
                            .expect("terminal store")
                            .push_result(
                                "Config",
                                format!("Could not save config value: {error:#}"),
                            );
                    }
                }
                set_page(
                    &ui,
                    page,
                    &field_values_for_controls.borrow(),
                    &mut data_source_cache_for_controls.borrow_mut(),
                    &bundle_root_for_controls,
                );
            }
        }
    });
    let ui_weak = ui.as_weak();
    let pages_for_actions = pages.clone();
    let selected_for_action = selected_page.clone();
    let field_values_for_actions = field_values.clone();
    let data_source_cache_for_actions = data_source_cache.clone();
    let bundle_root_for_actions = bundle_root.clone();
    let terminal_for_actions = terminal_store.clone();
    let running_for_actions = running_processes.clone();
    let exit_codes_for_actions = exit_code_reference.clone();
    let pending_confirmation = Rc::new(RefCell::new(None::<String>));
    let pending_for_actions = pending_confirmation.clone();
    ui.on_action_selected(move |index| {
        if let Some(ui) = ui_weak.upgrade() {
            let selected = *selected_for_action.borrow();
            if let Some(page) = pages_for_actions.get(selected) {
                let mut cache = data_source_cache_for_actions.borrow_mut();
                let effective_values = effective_field_values(
                    page,
                    &field_values_for_actions.borrow(),
                    &mut cache,
                    &bundle_root_for_actions,
                );
                let actions = visible_actions(
                    page,
                    &effective_values,
                    &mut cache,
                    &bundle_root_for_actions,
                );
                if let Some(action) = actions.get(index.max(0) as usize) {
                    let action_key = format!("{}:{}", selected, action.id);
                    if action.confirmation.is_some()
                        && pending_for_actions.borrow().as_deref() != Some(action_key.as_str())
                    {
                        *pending_for_actions.borrow_mut() = Some(action_key);
                        let prompt = confirmation_prompt(action, &effective_values)
                            .unwrap_or_else(|| "Click again to confirm.".to_string());
                        terminal_for_actions
                            .lock()
                            .expect("terminal store")
                            .push_result(format!("Confirm {}", action.title), prompt);
                    } else {
                        *pending_for_actions.borrow_mut() = None;
                        match prepare_action_command(
                            action,
                            &effective_values,
                            &bundle_root_for_actions,
                        ) {
                            Ok(command) => {
                                let command = command.with_exit_code_reference(
                                    exit_codes_for_actions.as_ref().clone(),
                                );
                                let title = action.title.clone();
                                let page_snapshot = page.clone();
                                let field_snapshot = field_values_for_actions.borrow().clone();
                                let bundle_root_snapshot = (*bundle_root_for_actions).clone();
                                let terminal_id = terminal_for_actions
                                    .lock()
                                    .expect("terminal store")
                                    .start_running(title, command.display());
                                update_terminal(
                                    &ui,
                                    &terminal_for_actions.lock().expect("terminal store"),
                                );
                                let terminal_for_finish = terminal_for_actions.clone();
                                let running_for_finish = running_for_actions.clone();
                                let ui_weak_for_finish = ui.as_weak();
                                thread::spawn(move || {
                                    let output = run_prepared_command_tracked(
                                        command,
                                        terminal_id,
                                        running_for_finish,
                                    );
                                    let _ = slint::invoke_from_event_loop(move || {
                                        if let Some(ui) = ui_weak_for_finish.upgrade() {
                                            terminal_for_finish
                                                .lock()
                                                .expect("terminal store")
                                                .finish_result(terminal_id, output);
                                            let mut refreshed_cache = BTreeMap::new();
                                            set_page(
                                                &ui,
                                                &page_snapshot,
                                                &field_snapshot,
                                                &mut refreshed_cache,
                                                &bundle_root_snapshot,
                                            );
                                            update_terminal(
                                                &ui,
                                                &terminal_for_finish
                                                    .lock()
                                                    .expect("terminal store"),
                                            );
                                        }
                                    });
                                });
                            }
                            Err(error) => {
                                terminal_for_actions
                                    .lock()
                                    .expect("terminal store")
                                    .push_result(
                                        action.title.clone(),
                                        format!("{} disabled: {error}", action.title),
                                    );
                            }
                        }
                    }
                    update_terminal(&ui, &terminal_for_actions.lock().expect("terminal store"));
                }
            }
        }
    });
    let ui_weak = ui.as_weak();
    let setup_steps_for_callback = setup_steps.clone();
    let pages_for_setup = pages.clone();
    let selected_for_setup = selected_page.clone();
    let field_values_for_setup = field_values.clone();
    let bundle_root_for_setup = bundle_root.clone();
    let terminal_for_setup = terminal_store.clone();
    let running_for_setup = running_processes.clone();
    let exit_codes_for_setup = exit_code_reference.clone();
    ui.on_setup_selected(move |index| {
        if let Some(ui) = ui_weak.upgrade() {
            if let Some(step) = setup_steps_for_callback.get(index.max(0) as usize) {
                match prepare_setup_command(step, &bundle_root_for_setup) {
                    Ok(command) => {
                        let command =
                            command.with_exit_code_reference(exit_codes_for_setup.as_ref().clone());
                        let selected = *selected_for_setup.borrow();
                        let page_snapshot = pages_for_setup.get(selected).cloned();
                        let field_snapshot = field_values_for_setup.borrow().clone();
                        let bundle_root_snapshot = (*bundle_root_for_setup).clone();
                        let terminal_id = terminal_for_setup
                            .lock()
                            .expect("terminal store")
                            .start_running(step.label.clone(), command.display());
                        update_terminal(&ui, &terminal_for_setup.lock().expect("terminal store"));
                        let terminal_for_finish = terminal_for_setup.clone();
                        let running_for_finish = running_for_setup.clone();
                        let ui_weak_for_finish = ui.as_weak();
                        thread::spawn(move || {
                            let output = run_prepared_command_tracked(
                                command,
                                terminal_id,
                                running_for_finish,
                            );
                            let _ = slint::invoke_from_event_loop(move || {
                                if let Some(ui) = ui_weak_for_finish.upgrade() {
                                    terminal_for_finish
                                        .lock()
                                        .expect("terminal store")
                                        .finish_result(terminal_id, output);
                                    if let Some(page) = page_snapshot {
                                        let mut refreshed_cache = BTreeMap::new();
                                        set_page(
                                            &ui,
                                            &page,
                                            &field_snapshot,
                                            &mut refreshed_cache,
                                            &bundle_root_snapshot,
                                        );
                                    }
                                    update_terminal(
                                        &ui,
                                        &terminal_for_finish.lock().expect("terminal store"),
                                    );
                                }
                            });
                        });
                    }
                    Err(error) => {
                        terminal_for_setup
                            .lock()
                            .expect("terminal store")
                            .push_result(
                                step.label.clone(),
                                format!("Could not prepare setup step {}: {error}", step.label),
                            );
                    }
                }
                update_terminal(&ui, &terminal_for_setup.lock().expect("terminal store"));
            }
        }
    });
    let ui_weak = ui.as_weak();
    let terminal_for_tabs = terminal_store.clone();
    ui.on_terminal_selected(move |index| {
        if let Some(ui) = ui_weak.upgrade() {
            terminal_for_tabs
                .lock()
                .expect("terminal store")
                .select(index.max(0) as usize);
            update_terminal(&ui, &terminal_for_tabs.lock().expect("terminal store"));
        }
    });
    let ui_weak = ui.as_weak();
    let terminal_for_tab_actions = terminal_store.clone();
    let running_for_tab_actions = running_processes.clone();
    ui.on_terminal_action(move |index| {
        if let Some(ui) = ui_weak.upgrade() {
            let action = terminal_for_tab_actions
                .lock()
                .expect("terminal store")
                .tab_action(index.max(0) as usize);
            if let Some(TerminalAction::Cancel(id)) = action {
                if let Err(error) = cancel_running_process(id, &running_for_tab_actions) {
                    terminal_for_tab_actions
                        .lock()
                        .expect("terminal store")
                        .push_result("Cancel", format!("Could not cancel command: {error:#}"));
                }
            }
            update_terminal(
                &ui,
                &terminal_for_tab_actions.lock().expect("terminal store"),
            );
        }
    });
    let ui_weak = ui.as_weak();
    let terminal_visible = Rc::new(RefCell::new(true));
    let terminal_visible_for_toggle = terminal_visible.clone();
    ui.on_terminal_toggle(move || {
        if let Some(ui) = ui_weak.upgrade() {
            let visible = !*terminal_visible_for_toggle.borrow();
            *terminal_visible_for_toggle.borrow_mut() = visible;
            ui.set_terminal_visible(visible);
        }
    });
    let ui_weak = ui.as_weak();
    let pages_for_paths = pages.clone();
    let selected_for_paths = selected_page.clone();
    let field_values_for_paths = field_values.clone();
    let data_source_cache_for_paths = data_source_cache.clone();
    let bundle_root_for_paths = bundle_root.clone();
    let persisted_for_paths = persisted_state.clone();
    let terminal_for_paths = terminal_store.clone();
    ui.on_path_picked(
        move |id: SharedString, label: SharedString, value: SharedString| {
            if let Some(ui) = ui_weak.upgrade() {
                match pick_path(&id, &label, &value, &bundle_root_for_paths) {
                    Ok(Some(path)) => {
                        field_values_for_paths
                            .borrow_mut()
                            .insert(id.to_string(), path.clone());
                        let selected = *selected_for_paths.borrow();
                        if let Some(page) = pages_for_paths.get(selected) {
                            if let Some(control) = control_for_id(page, &id) {
                                if control_persists_field_value(control) {
                                    persist_field_value(
                                        &mut persisted_for_paths.borrow_mut(),
                                        &id,
                                        &path,
                                    );
                                    if let Err(error) = save_state(
                                        &persisted_for_paths.borrow(),
                                        &bundle_root_for_paths,
                                    ) {
                                        terminal_for_paths
                                            .lock()
                                            .expect("terminal store")
                                            .push_result(
                                                "State",
                                                format!("Could not save picked path: {error:#}"),
                                            );
                                    }
                                }
                                if let Err(error) = save_config_value(control, &path) {
                                    terminal_for_paths
                                        .lock()
                                        .expect("terminal store")
                                        .push_result(
                                            "Config",
                                            format!("Could not save picked path: {error:#}"),
                                        );
                                }
                            }
                            set_page(
                                &ui,
                                page,
                                &field_values_for_paths.borrow(),
                                &mut data_source_cache_for_paths.borrow_mut(),
                                &bundle_root_for_paths,
                            );
                        }
                    }
                    Ok(None) => {}
                    Err(error) => {
                        terminal_for_paths
                            .lock()
                            .expect("terminal store")
                            .push_result("Path picker", format!("Could not pick path: {error:#}"));
                    }
                }
                update_terminal(&ui, &terminal_for_paths.lock().expect("terminal store"));
            }
        },
    );

    let ready_ms = started.elapsed().as_secs_f64() * 1000.0;
    let full_feature_warm_ms = if args.benchmark_full {
        let warm_started = Instant::now();
        warm_all_pages(
            &pages,
            &field_values.borrow(),
            &mut data_source_cache.borrow_mut(),
            &bundle_root,
        );
        Some(warm_started.elapsed().as_secs_f64() * 1000.0)
    } else {
        None
    };
    if args.benchmark {
        let full_feature_warm = full_feature_warm_ms
            .map(|value| format!(" full_feature_warm_ms={value:.1}"))
            .unwrap_or_default();
        let loaded_data_sources = data_source_cache.borrow().len();
        println!(
            "gfc-slint benchmark bundle_loaded_ms={loaded_ms:.1} ui_ready_ms={ready_ms:.1}{full_feature_warm} pages={} controls={control_count} actions={action_count} setup_steps={} data_sources={data_source_count} data_sources_loaded={loaded_data_sources}",
            pages.len(),
            setup_steps.len()
        );
    }

    if args.once {
        return Ok(());
    }

    ui.run().context("run Slint window")
}

fn set_page(
    ui: &AppWindow,
    page: &PageView,
    field_values: &BTreeMap<String, String>,
    data_source_cache: &mut BTreeMap<String, String>,
    bundle_root: &Path,
) {
    ui.set_page_title(SharedString::from(page.title.as_str()));
    ui.set_page_summary(SharedString::from(page.summary.as_str()));
    ui.set_page_body(SharedString::from(page.body.as_str()));
    let effective_values =
        effective_field_values(page, field_values, data_source_cache, bundle_root);
    let actions = visible_actions(page, &effective_values, data_source_cache, bundle_root)
        .iter()
        .map(|action| PageAction {
            title: action.title.as_str().into(),
            command: action_label(action, &effective_values).as_str().into(),
            enabled: action_unavailable_reason(action, &effective_values).is_none(),
        })
        .collect::<Vec<_>>();
    ui.set_actions(ModelRc::new(Rc::new(VecModel::from(actions))));
    let controls = page
        .controls
        .iter()
        .map(|control| {
            let value = field_values
                .get(&control.id)
                .cloned()
                .unwrap_or_else(|| control.value.clone());
            PageControl {
                id: control.id.as_str().into(),
                label: control.label.as_str().into(),
                kind: control.kind.as_str().into(),
                value: value.as_str().into(),
                placeholder: control.placeholder.as_str().into(),
                helper: control.helper.as_str().into(),
                options: control_options(control, field_values, data_source_cache, bundle_root)
                    .as_str()
                    .into(),
            }
        })
        .collect::<Vec<_>>();
    ui.set_controls(ModelRc::new(Rc::new(VecModel::from(controls))));
}

fn warm_all_pages(
    pages: &[PageView],
    field_values: &BTreeMap<String, String>,
    data_source_cache: &mut BTreeMap<String, String>,
    bundle_root: &Path,
) {
    for page in pages {
        let effective_values =
            effective_field_values(page, field_values, data_source_cache, bundle_root);
        let _ = visible_actions(page, &effective_values, data_source_cache, bundle_root);
        for control in &page.controls {
            let _ = control_options(control, &effective_values, data_source_cache, bundle_root);
        }
    }
}

fn visible_actions(
    page: &PageView,
    field_values: &BTreeMap<String, String>,
    data_source_cache: &mut BTreeMap<String, String>,
    bundle_root: &Path,
) -> Vec<bundle::ActionView> {
    let mut actions = page
        .actions
        .iter()
        .filter(|action| is_action_visible(action, field_values))
        .cloned()
        .collect::<Vec<_>>();
    match data_source_row_actions(&page.controls, field_values, data_source_cache, bundle_root) {
        Ok(row_actions) => actions.extend(row_actions),
        Err(error) => eprintln!("Could not load row actions: {error:#}"),
    }
    actions
}

fn control_for_id<'a>(page: &'a PageView, id: &str) -> Option<&'a bundle::ControlView> {
    page.controls.iter().find(|control| control.id == id)
}

fn effective_field_values(
    page: &PageView,
    field_values: &BTreeMap<String, String>,
    data_source_cache: &mut BTreeMap<String, String>,
    bundle_root: &Path,
) -> BTreeMap<String, String> {
    let mut values = field_values.clone();
    values.extend(data_source_values(
        &page.controls,
        field_values,
        data_source_cache,
        bundle_root,
    ));
    values
}

fn action_label(action: &bundle::ActionView, field_values: &BTreeMap<String, String>) -> String {
    if let Some(reason) = action_unavailable_reason(action, field_values) {
        format!("disabled: {reason}")
    } else {
        let role = if action.role == "primary" {
            String::new()
        } else {
            format!("{} ", action.role)
        };
        format!("{role}{}", action_preview(action, field_values))
    }
}

fn update_terminal(ui: &AppWindow, terminal: &TerminalStore) {
    let tabs = terminal
        .entries()
        .iter()
        .map(|entry| TerminalTab {
            title: entry.title.as_str().into(),
            status: status_label(entry.status).into(),
            action: if entry.closable {
                match entry.status {
                    TerminalStatus::Running => "Cancel",
                    _ => "Close",
                }
            } else {
                ""
            }
            .into(),
        })
        .collect::<Vec<_>>();
    ui.set_terminal_tabs(ModelRc::new(Rc::new(VecModel::from(tabs))));
    ui.set_terminal_output(SharedString::from(terminal.selected_output()));
}

#[cfg(test)]
mod layout_tests {
    const MAIN_SOURCE: &str = include_str!("main.rs");

    #[test]
    fn app_window_uses_resizable_constraints() {
        assert!(MAIN_SOURCE.contains("preferred-width: 1120px;"));
        assert!(MAIN_SOURCE.contains("preferred-height: 720px;"));
        assert!(MAIN_SOURCE.contains("min-width: 720px;"));
        assert!(MAIN_SOURCE.contains("min-height: 480px;"));
        assert!(!MAIN_SOURCE.contains("\n        width: 1120px;"));
        assert!(!MAIN_SOURCE.contains("\n        height: 720px;"));
    }

    #[test]
    fn wide_page_content_is_allowed_to_shrink() {
        let required_markers = [
            "horizontal-stretch: 1;",
            "min-width: 0px;",
            "text: action.command;",
            "text: root.terminal-output;",
        ];
        for marker in required_markers {
            assert!(
                MAIN_SOURCE.contains(marker),
                "missing layout marker: {marker}"
            );
        }
        assert!(!MAIN_SOURCE.contains("text: action.title + \" — \" + action.command;"));
        assert!(!MAIN_SOURCE.contains("text: setup.title + \" — \" + setup.command;"));
    }

    #[test]
    fn terminal_drawer_is_bottom_panel_with_hide_show_affordance() {
        let required_markers = [
            "in property <bool> terminal-visible: true;",
            "callback terminal-toggle();",
            "if root.terminal-visible : Rectangle",
            "height: 180px;",
            "text: \"Hide terminal\";",
            "text: \"Show terminal\";",
        ];
        for marker in required_markers {
            assert!(
                MAIN_SOURCE.contains(marker),
                "missing terminal drawer marker: {marker}"
            );
        }
    }
}
