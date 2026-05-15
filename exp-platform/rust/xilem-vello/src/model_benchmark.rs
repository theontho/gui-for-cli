use crate::control_text::control_options;
use crate::model::XilemModel;
use anyhow::{Context, Result, anyhow};
use std::fs;
use std::path::Path;
use std::time::Instant;

impl XilemModel {
    pub fn check_summary(&self) -> String {
        format!(
            "Loaded {} pages, {} controls, {} actions, {} setup steps, {} data sources from {} using {} layout and {} terminal text",
            self.pages.len(),
            self.control_count,
            self.action_count,
            self.setup_steps.len(),
            self.data_source_count,
            self.bundle_root.display(),
            self.interface_direction,
            self.terminal_text_direction
        )
    }

    pub fn print_check_summary(&self) {
        println!("{}", self.check_summary());
    }

    pub fn benchmark_summary(&mut self) -> String {
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
        format!(
            "gfc-xilem-vello benchmark first_render_marker=core-ready bundle_loaded_ms={:.1} ui_ready_ms={:.1}{full_feature_warm} pages={} controls={} actions={} setup_steps={} data_sources={} data_sources_loaded={} terminal_text_direction={}",
            self.loaded_ms,
            self.ready_ms,
            self.pages.len(),
            self.control_count,
            self.action_count,
            self.setup_steps.len(),
            self.data_source_count,
            self.data_source_cache.len(),
            self.terminal_text_direction
        )
    }

    pub fn emit_benchmark(&mut self, output_path: Option<&Path>) -> Result<()> {
        let message = self.benchmark_summary();
        println!("{message}");
        if let Some(path) = output_path {
            reject_forbidden_output_path(path)?;
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent)
                    .with_context(|| format!("create {}", parent.display()))?;
            }
            fs::write(path, format!("{message}\n"))
                .with_context(|| format!("write benchmark marker {}", path.display()))?;
        }
        Ok(())
    }

    pub fn warm_all_pages(&mut self) {
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
            }
        }
    }
}

fn reject_forbidden_output_path(path: &Path) -> Result<()> {
    let display = path.display().to_string();
    if display == "/tmp"
        || display.starts_with("/tmp/")
        || display == "/var/tmp"
        || display.starts_with("/var/tmp/")
    {
        Err(anyhow!(
            "benchmark output cannot be written to forbidden temp path: {display}"
        ))
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn rejects_forbidden_benchmark_outputs() {
        assert!(reject_forbidden_output_path(&PathBuf::from("/tmp/xilem.txt")).is_err());
        assert!(reject_forbidden_output_path(&PathBuf::from("/var/tmp")).is_err());
        assert!(reject_forbidden_output_path(&PathBuf::from("out/xilem.txt")).is_ok());
    }
}
