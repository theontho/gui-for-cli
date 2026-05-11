use slint::SharedString;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminalStatus {
    Ready,
    Ok,
    Warning,
    Failed,
}

#[derive(Debug, Clone)]
pub struct TerminalEntry {
    pub title: String,
    pub status: TerminalStatus,
    pub output: String,
}

#[derive(Debug)]
pub struct TerminalStore {
    entries: Vec<TerminalEntry>,
    selected: usize,
}

impl TerminalStore {
    pub fn new() -> Self {
        Self {
            entries: vec![TerminalEntry {
                title: "Main".to_string(),
                status: TerminalStatus::Ready,
                output: "Ready.".to_string(),
            }],
            selected: 0,
        }
    }

    pub fn entries(&self) -> &[TerminalEntry] {
        &self.entries
    }

    pub fn selected_output(&self) -> SharedString {
        self.entries
            .get(self.selected)
            .map(|entry| entry.output.as_str())
            .unwrap_or("Ready.")
            .into()
    }

    pub fn select(&mut self, index: usize) {
        if index < self.entries.len() {
            self.selected = index;
        }
    }

    pub fn push_result(&mut self, title: impl Into<String>, output: impl Into<String>) {
        let output = output.into();
        let status = status_for_output(&output);
        self.entries.push(TerminalEntry {
            title: title.into(),
            status,
            output,
        });
        if self.entries.len() > 40 {
            let overflow = self.entries.len() - 40;
            self.entries.drain(0..overflow);
            self.selected = self.selected.saturating_sub(overflow);
        }
        self.selected = self.entries.len().saturating_sub(1);
    }

    pub fn replace_main(&mut self, output: impl Into<String>) {
        if let Some(entry) = self.entries.first_mut() {
            entry.output = output.into();
            entry.status = status_for_output(&entry.output);
        }
    }
}

pub fn status_label(status: TerminalStatus) -> &'static str {
    match status {
        TerminalStatus::Ready => "ready",
        TerminalStatus::Ok => "ok",
        TerminalStatus::Warning => "warning",
        TerminalStatus::Failed => "failed",
    }
}

fn status_for_output(output: &str) -> TerminalStatus {
    if output.contains("[timeout]") || output.contains("truncated:") {
        TerminalStatus::Warning
    } else if output.contains("Could not ")
        || output.contains("Cannot run ")
        || output.contains("disabled:")
        || output.contains("exit 1]")
        || output.contains("exit 2]")
        || output.contains("exit 127]")
    {
        TerminalStatus::Failed
    } else {
        TerminalStatus::Ok
    }
}
