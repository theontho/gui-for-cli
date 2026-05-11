mod args;
mod bundle;
mod control_text;
mod execution;
mod path_picker;
mod state;
mod terminal;

use anyhow::{Context, Result, anyhow};
use args::{configure_default_renderer, parse_args};
use bundle::{PageView, load_bundle};
use control_text::{control_options, data_source_values, setup_command_preview};
use execution::{
    action_preview, confirmation_prompt, disabled_reason, is_action_visible, run_action,
    run_setup_step,
};
use path_picker::pick_path;
use slint::{ComponentHandle, ModelRc, SharedString, VecModel};
use state::{
    PersistedState, initial_field_values, load_state, persist_field_value, persist_selected_page,
    save_config_value, save_state, selected_page_index,
};
use std::cell::RefCell;
use std::collections::BTreeMap;
use std::path::Path;
use std::rc::Rc;
use std::time::Instant;
use terminal::{TerminalStore, status_label};

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
    }

    export component AppWindow inherits Window {
        in property <string> window-title;
        in property <string> bundle-summary;
        in property <string> setup-summary;
        in property <string> page-title;
        in property <string> page-summary;
        in property <string> page-body;
        in property <string> terminal-output;
        in property <[PageTab]> pages;
        in property <[PageAction]> actions;
        in property <[SetupAction]> setup-actions;
        in property <[PageControl]> controls;
        in property <[TerminalTab]> terminal-tabs;
        callback page-selected(int);
        callback action-selected(int);
        callback setup-selected(int);
        callback terminal-selected(int);
        callback control-edited(string, string);
        callback path-picked(string, string, string);

        title: root.window-title;
        width: 1120px;
        height: 720px;
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

                      for setup[index] in root.setup-actions : Button {
                          text: setup.title + " — " + setup.command;
                          clicked => {
                              root.setup-selected(index);
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
                         VerticalLayout {
                             spacing: 12px;

                              Text {
                                  text: root.page-body;
                                  wrap: word-wrap;
                                  color: #263044;
                                  font-size: 15px;
                              }

                              for control in root.controls : Rectangle {
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
                                           text: control.options == "" ? control.value : control.options;
                                           wrap: word-wrap;
                                           color: #566070;
                                      }

                                      if control.kind == "dropdown" || control.kind == "checkboxGroup" : Text {
                                          text: control.options;
                                          wrap: word-wrap;
                                          color: #566070;
                                          font-size: 12px;
                                      }

                                      Text {
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

                              for action[index] in root.actions : Button {
                                  text: action.title + " — " + action.command;
                                  enabled: action.enabled;
                                  clicked => {
                                      root.action-selected(index);
                                  }
                              }

                             Rectangle { height: 1px; background: #e4e7ef; }

                              HorizontalLayout {
                                  spacing: 6px;
                                  for tab[index] in root.terminal-tabs : Button {
                                      text: tab.title + " [" + tab.status + "]";
                                      clicked => {
                                          root.terminal-selected(index);
                                      }
                                  }
                              }

                              ScrollView {
                                  Text {
                                      text: root.terminal-output;
                                      wrap: word-wrap;
                                      color: #263044;
                                      font-size: 13px;
                                  }
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
    let bundle = load_bundle(&args.bundle, &args.repo_root, &args.locale)?;
    let loaded_ms = started.elapsed().as_secs_f64() * 1000.0;
    configure_default_renderer();

    let mut startup_messages = Vec::new();
    let persisted = match load_state() {
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
    let terminal_store = Rc::new(RefCell::new(TerminalStore::new()));
    if !startup_messages.is_empty() {
        terminal_store
            .borrow_mut()
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
    let bundle_root = Rc::new(args.bundle.clone());
    let pages = Rc::new(bundle.pages);
    let first_page = pages
        .get(selected_index)
        .or_else(|| pages.first())
        .ok_or_else(|| anyhow!("bundle has no pages"))?;

    let ui = AppWindow::new().context("create Slint window")?;
    ui.set_window_title(bundle.title.as_str().into());
    ui.set_bundle_summary(bundle.summary.as_str().into());
    ui.set_setup_summary(bundle.setup_lines.join("\n").as_str().into());
    update_terminal(&ui, &terminal_store.borrow());
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
                if let Err(error) = save_state(&persisted_for_page.borrow()) {
                    terminal_for_page
                        .borrow_mut()
                        .push_result("State", format!("Could not save selected page: {error:#}"));
                    update_terminal(&ui, &terminal_for_page.borrow());
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
        persist_field_value(&mut persisted_for_controls.borrow_mut(), &id, &value);
        if let Err(error) = save_state(&persisted_for_controls.borrow()) {
            if let Some(ui) = ui_weak.upgrade() {
                terminal_for_controls
                    .borrow_mut()
                    .push_result("State", format!("Could not save field value: {error:#}"));
                update_terminal(&ui, &terminal_for_controls.borrow());
            }
        }
        if let Some(ui) = ui_weak.upgrade() {
            let selected = *selected_for_controls.borrow();
            if let Some(page) = pages_for_controls.get(selected) {
                if let Some(control) = control_for_id(page, &id) {
                    if let Err(error) = save_config_value(control, &value) {
                        terminal_for_controls.borrow_mut().push_result(
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
    let pending_confirmation = Rc::new(RefCell::new(None::<String>));
    let pending_for_actions = pending_confirmation.clone();
    ui.on_action_selected(move |index| {
        if let Some(ui) = ui_weak.upgrade() {
            let selected = *selected_for_action.borrow();
            if let Some(page) = pages_for_actions.get(selected) {
                let effective_values = effective_field_values(
                    page,
                    &field_values_for_actions.borrow(),
                    &mut data_source_cache_for_actions.borrow_mut(),
                    &bundle_root_for_actions,
                );
                let actions = visible_actions(page, &effective_values);
                if let Some(action) = actions.get(index.max(0) as usize) {
                    let action_key = format!("{}:{}", selected, action.id);
                    if action.confirmation.is_some()
                        && pending_for_actions.borrow().as_deref() != Some(action_key.as_str())
                    {
                        *pending_for_actions.borrow_mut() = Some(action_key);
                        let prompt = confirmation_prompt(action, &effective_values)
                            .unwrap_or_else(|| "Click again to confirm.".to_string());
                        terminal_for_actions
                            .borrow_mut()
                            .push_result(format!("Confirm {}", action.title), prompt);
                    } else {
                        *pending_for_actions.borrow_mut() = None;
                        let output =
                            run_action(action, &effective_values, &bundle_root_for_actions);
                        terminal_for_actions
                            .borrow_mut()
                            .push_result(action.title.clone(), output);
                    }
                    update_terminal(&ui, &terminal_for_actions.borrow());
                }
            }
        }
    });
    let ui_weak = ui.as_weak();
    let setup_steps_for_callback = setup_steps.clone();
    let bundle_root_for_setup = bundle_root.clone();
    let terminal_for_setup = terminal_store.clone();
    ui.on_setup_selected(move |index| {
        if let Some(ui) = ui_weak.upgrade() {
            if let Some(step) = setup_steps_for_callback.get(index.max(0) as usize) {
                let output = run_setup_step(step, &bundle_root_for_setup);
                terminal_for_setup
                    .borrow_mut()
                    .push_result(step.label.clone(), output);
                update_terminal(&ui, &terminal_for_setup.borrow());
            }
        }
    });
    let ui_weak = ui.as_weak();
    let terminal_for_tabs = terminal_store.clone();
    ui.on_terminal_selected(move |index| {
        if let Some(ui) = ui_weak.upgrade() {
            terminal_for_tabs.borrow_mut().select(index.max(0) as usize);
            update_terminal(&ui, &terminal_for_tabs.borrow());
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
                        persist_field_value(&mut persisted_for_paths.borrow_mut(), &id, &path);
                        if let Err(error) = save_state(&persisted_for_paths.borrow()) {
                            terminal_for_paths.borrow_mut().push_result(
                                "State",
                                format!("Could not save picked path: {error:#}"),
                            );
                        }
                        let selected = *selected_for_paths.borrow();
                        if let Some(page) = pages_for_paths.get(selected) {
                            if let Some(control) = control_for_id(page, &id) {
                                if let Err(error) = save_config_value(control, &path) {
                                    terminal_for_paths.borrow_mut().push_result(
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
                            .borrow_mut()
                            .push_result("Path picker", format!("Could not pick path: {error:#}"));
                    }
                }
                update_terminal(&ui, &terminal_for_paths.borrow());
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
    let actions = page
        .actions
        .iter()
        .filter(|action| is_action_visible(action, &effective_values))
        .map(|action| PageAction {
            title: action.title.as_str().into(),
            command: action_label(action, &effective_values).as_str().into(),
            enabled: disabled_reason(action, &effective_values).is_none(),
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
        for control in &page.controls {
            let _ = control_options(control, field_values, data_source_cache, bundle_root);
        }
    }
}

fn visible_actions<'a>(
    page: &'a PageView,
    field_values: &BTreeMap<String, String>,
) -> Vec<&'a bundle::ActionView> {
    page.actions
        .iter()
        .filter(|action| is_action_visible(action, field_values))
        .collect()
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
    if let Some(reason) = disabled_reason(action, field_values) {
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
        })
        .collect::<Vec<_>>();
    ui.set_terminal_tabs(ModelRc::new(Rc::new(VecModel::from(tabs))));
    ui.set_terminal_output(terminal.selected_output());
}
