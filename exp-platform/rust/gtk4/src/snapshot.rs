use crate::app_model::GtkAppModel;
use crate::bundle::{ActionView, ControlView, PageView};
use crate::control_text::{control_options, setup_command_preview};
use crate::execution::{action_preview, action_unavailable_reason};
use crate::row_actions::{DataSourceRowView, data_source_rows};
use crate::terminal::TerminalEntry;
use std::collections::BTreeMap;
use std::time::Instant;

pub struct UiSnapshot {
    pub title: String,
    pub summary: String,
    pub setup_lines: Vec<String>,
    pub setup_steps: Vec<SetupSnapshot>,
    pub pages: Vec<PageSnapshot>,
    pub selected_page: usize,
    pub current_page: Option<PageView>,
    pub controls: Vec<ControlSnapshot>,
    pub actions: Vec<ActionSnapshot>,
    pub terminal_entries: Vec<TerminalEntry>,
    pub selected_terminal: usize,
    pub terminal_visible: bool,
    pub terminal_text_direction: String,
    pub is_rtl: bool,
    pub labels: BTreeMap<String, String>,
    pub workspace_path: String,
}

pub struct PageSnapshot {
    pub title: String,
}

pub struct SetupSnapshot {
    pub label: String,
    pub command: String,
    pub running: bool,
}

pub struct ControlSnapshot {
    pub control: ControlView,
    pub value: String,
    pub detail: String,
    pub rows: Result<Vec<DataSourceRowView>, String>,
}

pub struct ActionSnapshot {
    pub action: ActionView,
    pub preview: String,
    pub disabled_reason: Option<String>,
    pub running: bool,
}

impl GtkAppModel {
    pub fn snapshot(&mut self) -> UiSnapshot {
        self.poll_finished_commands();
        let current_page = self.current_page().cloned();
        let (controls, actions) = if let Some(page) = &current_page {
            let effective_values = self.effective_field_values(page);
            let controls = page
                .controls
                .iter()
                .cloned()
                .map(|control| self.control_snapshot(control, &effective_values))
                .collect();
            let actions = self
                .visible_actions(page, &effective_values)
                .into_iter()
                .map(|action| ActionSnapshot {
                    preview: action_preview(&action, &effective_values),
                    disabled_reason: action_unavailable_reason(&action, &effective_values),
                    running: self.running_action_ids.contains(&action.id),
                    action,
                })
                .collect();
            (controls, actions)
        } else {
            (Vec::new(), Vec::new())
        };
        UiSnapshot {
            title: self.title.clone(),
            summary: self.summary.clone(),
            setup_lines: self.setup_lines.clone(),
            setup_steps: self
                .setup_steps
                .iter()
                .enumerate()
                .map(|(index, step)| SetupSnapshot {
                    label: step.label.clone(),
                    command: setup_command_preview(step),
                    running: self.running_setup_indexes.contains(&index),
                })
                .collect(),
            pages: self
                .pages
                .iter()
                .map(|page| PageSnapshot {
                    title: page.title.clone(),
                })
                .collect(),
            selected_page: self.selected_page,
            current_page,
            controls,
            actions,
            terminal_entries: self.terminal.entries().to_vec(),
            selected_terminal: self.terminal.selected_index(),
            terminal_visible: self.terminal_visible,
            terminal_text_direction: self.terminal_text_direction.clone(),
            is_rtl: self.interface_direction == "rtl",
            labels: self.labels.clone(),
            workspace_path: self.bundle_root.display().to_string(),
        }
    }

    pub fn print_benchmark_if_requested(&mut self) {
        if !self.benchmark {
            return;
        }
        let full_feature_warm_ms = if self.benchmark_full {
            let started = Instant::now();
            self.warm_all_pages();
            Some(started.elapsed().as_secs_f64() * 1000.0)
        } else {
            None
        };
        let full_feature_warm = full_feature_warm_ms
            .map(|value| format!(" full_feature_warm_ms={value:.1}"))
            .unwrap_or_default();
        println!(
            "gfc-gtk4 benchmark bundle_loaded_ms={:.1} ui_ready_ms={:.1}{full_feature_warm} pages={} controls={} actions={} setup_steps={} data_sources={} data_sources_loaded={} terminal_text_direction={}",
            self.loaded_ms,
            self.ready_ms,
            self.pages.len(),
            self.control_count,
            self.action_count,
            self.setup_steps.len(),
            self.data_source_count,
            self.data_source_cache.len(),
            self.terminal_text_direction
        );
    }

    fn control_snapshot(
        &mut self,
        control: ControlView,
        effective_values: &BTreeMap<String, String>,
    ) -> ControlSnapshot {
        let value = self
            .field_values
            .get(&control.id)
            .cloned()
            .unwrap_or_else(|| control.value.clone());
        let detail = control_options(
            &control,
            effective_values,
            &mut self.data_source_cache,
            &self.bundle_root,
        );
        let rows = if control.data_source.is_some() {
            data_source_rows(
                &control,
                effective_values,
                &mut self.data_source_cache,
                &self.bundle_root,
            )
            .map_err(|error| format!("{error:#}"))
        } else {
            Ok(Vec::new())
        };
        ControlSnapshot {
            control,
            value,
            detail,
            rows,
        }
    }

    fn warm_all_pages(&mut self) {
        for page in self.pages.clone() {
            let effective_values = self.effective_field_values(&page);
            let _ = self.visible_actions(&page, &effective_values);
            for control in &page.controls {
                let _ = control_options(
                    control,
                    &effective_values,
                    &mut self.data_source_cache,
                    &self.bundle_root,
                );
                let _ = data_source_rows(
                    control,
                    &effective_values,
                    &mut self.data_source_cache,
                    &self.bundle_root,
                );
            }
        }
    }
}
