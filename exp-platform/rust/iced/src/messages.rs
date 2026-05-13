use crate::bundle::ActionView;

#[derive(Debug, Clone)]
pub enum Message {
    SelectPage(usize),
    ToggleSidebar,
    ToggleTerminal,
    SetTerminalHeight(f32),
    SetFontScale(f32),
    ControlChanged(String, String),
    PickPath(String),
    RunSetup(usize),
    RunAction(ActionView),
    TerminalSelect(usize),
    TerminalTabAction(usize),
    OpenWorkspace,
    CommandFinished(CommandFinished),
}

#[derive(Debug, Clone)]
pub struct CommandFinished {
    pub terminal_id: u64,
    pub action_id: Option<String>,
    pub setup_index: Option<usize>,
    pub output: String,
}
