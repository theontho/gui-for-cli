use crate::app::IcedApp;
use anyhow::{Context, Result, anyhow};
use std::fs;
use std::path::PathBuf;
use std::time::Instant;

impl IcedApp {
    pub fn benchmark_enabled(&self) -> bool {
        self.benchmark
    }

    pub fn print_check_summary(&self) {
        println!(
            "Loaded {} pages, {} controls, {} actions, {} setup steps, {} data sources from {}",
            self.pages.len(),
            self.control_count,
            self.action_count,
            self.setup_steps.len(),
            self.data_source_count,
            self.bundle_root.display()
        );
    }

    pub fn print_benchmark_summary(&self) -> Result<()> {
        let started = Instant::now();
        if self.benchmark_full {
            self.warm_all_pages();
        }
        let full_feature_warm = if self.benchmark_full {
            format!(
                " full_feature_warm_ms={:.1}",
                started.elapsed().as_secs_f64() * 1000.0
            )
        } else {
            String::new()
        };
        let message = format!(
            "gfc-iced benchmark bundle_loaded_ms={:.1} ui_ready_ms={:.1}{full_feature_warm} pages={} controls={} actions={} setup_steps={} data_sources={} data_sources_loaded={} terminal_text_direction={}",
            self.loaded_ms,
            self.ready_ms,
            self.pages.len(),
            self.control_count,
            self.action_count,
            self.setup_steps.len(),
            self.data_source_count,
            self.data_source_cache.borrow().len(),
            self.terminal_text_direction,
        );
        println!("{message}");
        if let Some(path) = &self.benchmark_output {
            reject_forbidden_temp_path(path)?;
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent)
                    .with_context(|| format!("create {}", parent.display()))?;
            }
            fs::write(path, format!("{message}\n"))
                .with_context(|| format!("write benchmark marker {}", path.display()))?;
        }
        Ok(())
    }

    fn warm_all_pages(&self) {
        for page in &self.pages {
            let values = self.effective_field_values(page);
            let _ = self.visible_actions(page, &values);
            for control in &page.controls {
                let _ = self.control_details(control);
            }
        }
    }
}

fn reject_forbidden_temp_path(path: &PathBuf) -> Result<()> {
    let text = path.display().to_string();
    if text == "/tmp" || text.starts_with("/tmp/") || text.starts_with("/var/tmp/") {
        return Err(anyhow!(
            "benchmark output must not be written under /tmp or /var/tmp"
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_forbidden_benchmark_outputs() {
        assert!(reject_forbidden_temp_path(&PathBuf::from("/tmp/iced.json")).is_err());
        assert!(reject_forbidden_temp_path(&PathBuf::from("out/iced.json")).is_ok());
    }
}
