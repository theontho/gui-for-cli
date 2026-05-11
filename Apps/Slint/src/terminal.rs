use slint::SharedString;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminalStatus {
    Ready,
    Running,
    Ok,
    Warning,
    Failed,
}

#[derive(Debug, Clone)]
pub struct TerminalEntry {
    pub id: u64,
    pub title: String,
    pub status: TerminalStatus,
    pub output: String,
    pub closable: bool,
}

#[derive(Debug)]
pub struct TerminalStore {
    entries: Vec<TerminalEntry>,
    selected: usize,
    next_id: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminalAction {
    Cancel(u64),
    Close,
}

impl TerminalStore {
    pub fn new() -> Self {
        Self {
            entries: vec![TerminalEntry {
                id: 0,
                title: "Main".to_string(),
                status: TerminalStatus::Ready,
                output: "Ready.".to_string(),
                closable: false,
            }],
            selected: 0,
            next_id: 1,
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
        let id = self.allocate_id();
        self.entries.push(TerminalEntry {
            id,
            title: title.into(),
            status,
            output,
            closable: true,
        });
        self.trim_entries();
        self.selected = self.entries.len().saturating_sub(1);
    }

    pub fn start_running(&mut self, title: impl Into<String>, command: impl Into<String>) -> u64 {
        let id = self.allocate_id();
        self.entries.push(TerminalEntry {
            id,
            title: title.into(),
            status: TerminalStatus::Running,
            output: format!("$ {}\n[running]", command.into()),
            closable: true,
        });
        self.trim_entries();
        self.selected = self.entries.len().saturating_sub(1);
        id
    }

    pub fn finish_result(&mut self, id: u64, output: impl Into<String>) {
        let output = output.into();
        if let Some((index, entry)) = self
            .entries
            .iter_mut()
            .enumerate()
            .find(|(_, entry)| entry.id == id)
        {
            entry.output = output;
            entry.status = status_for_output(&entry.output);
            self.selected = index;
        } else {
            self.push_result("Completed command", output);
        }
    }

    pub fn tab_action(&mut self, index: usize) -> Option<TerminalAction> {
        if index == 0 || index >= self.entries.len() || !self.entries[index].closable {
            return None;
        }
        if self.entries[index].status == TerminalStatus::Running {
            self.entries[index].status = TerminalStatus::Warning;
            self.entries[index]
                .output
                .push_str("\n[cancellation requested]");
            self.selected = index;
            Some(TerminalAction::Cancel(self.entries[index].id))
        } else {
            self.entries.remove(index);
            self.selected = self
                .selected
                .saturating_sub(usize::from(index <= self.selected))
                .min(self.entries.len().saturating_sub(1));
            Some(TerminalAction::Close)
        }
    }

    pub fn replace_main(&mut self, output: impl Into<String>) {
        if let Some(entry) = self.entries.first_mut() {
            entry.output = output.into();
            entry.status = status_for_output(&entry.output);
        }
    }

    fn allocate_id(&mut self) -> u64 {
        let id = self.next_id;
        self.next_id = self.next_id.saturating_add(1);
        id
    }

    fn trim_entries(&mut self) {
        if self.entries.len() > 40 {
            let overflow = self.entries.len() - 40;
            self.entries.drain(1..=overflow);
            self.selected = self.selected.saturating_sub(overflow).max(1);
        }
    }
}

pub fn status_label(status: TerminalStatus) -> &'static str {
    match status {
        TerminalStatus::Ready => "ready",
        TerminalStatus::Running => "running",
        TerminalStatus::Ok => "ok",
        TerminalStatus::Warning => "warning",
        TerminalStatus::Failed => "failed",
    }
}

fn status_for_output(output: &str) -> TerminalStatus {
    if output.contains("[timeout]")
        || output.contains("truncated:")
        || output.contains("[exit warning]")
    {
        TerminalStatus::Warning
    } else if output.contains("Could not ")
        || output.contains("Cannot run ")
        || output.contains("disabled:")
        || (output.contains(" exit ") && !output.contains(" exit 0]"))
    {
        TerminalStatus::Failed
    } else {
        TerminalStatus::Ok
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn running_tabs_can_be_cancelled_then_finished() {
        let mut store = TerminalStore::new();
        let id = store.start_running("Align", "tool --input reads.fastq");

        assert_eq!(store.entries()[1].status, TerminalStatus::Running);
        assert_eq!(store.tab_action(1), Some(TerminalAction::Cancel(id)));
        assert_eq!(store.entries()[1].status, TerminalStatus::Warning);

        store.finish_result(id, "$ tool --input reads.fastq\n[Align exit 0]");
        assert_eq!(store.entries()[1].status, TerminalStatus::Ok);
        assert_eq!(store.tab_action(1), Some(TerminalAction::Close));
        assert_eq!(store.entries().len(), 1);
    }

    #[test]
    fn main_terminal_tab_cannot_be_closed() {
        let mut store = TerminalStore::new();

        assert_eq!(store.tab_action(0), None);
        assert_eq!(store.entries().len(), 1);
    }

    #[test]
    fn manifest_warning_exit_codes_mark_tabs_warning() {
        let mut store = TerminalStore::new();

        store.push_result(
            "Estimate",
            "$ estimate\n[exit warning] Disk estimate failed\n[exit explanation] Check storage.\n[Estimate exit 42]",
        );

        assert_eq!(store.entries()[1].status, TerminalStatus::Warning);
    }
}
