use crate::app::IcedApp;
use crate::messages::Message;
use crate::terminal::{TerminalEntry, TerminalStatus};
use crate::view_values::{scaled_size, status_icon, status_label_key};
use iced::widget::{button, column, container, horizontal_rule, row, scrollable, text};
use iced::{Alignment, Element, Font, Length};

pub fn terminal_panel(app: &IcedApp) -> Element<'_, Message> {
    if !app.terminal_visible {
        return container(
            button(text(app.label("app.terminal.showOutput.label")))
                .on_press(Message::ToggleTerminal),
        )
        .padding(8)
        .width(Length::Fill)
        .into();
    }

    let mut tabs = row![
        text(app.label("app.terminal.commandOutput.label")).size(scaled_size(14.0, app.font_scale)),
    ]
    .spacing(6)
    .align_y(Alignment::Center);

    for (index, entry) in app.terminal.entries().iter().enumerate() {
        tabs = tabs
            .push(tab_button(app, index, entry))
            .push(tab_action_button(app, index, entry));
    }

    let hide =
        button(text(app.label("app.terminal.hideOutput.label"))).on_press(Message::ToggleTerminal);
    tabs = tabs.push(hide);

    let mut panel = column![tabs, horizontal_rule(1)].spacing(6);
    if let Some(entry) = app.terminal.selected_entry() {
        if let Some(detail) = terminal_status_detail(app, entry) {
            panel = panel.push(text(detail).size(scaled_size(12.0, app.font_scale)));
        }
    }
    if app.terminal_text_direction == "rtl" {
        panel = panel.push(text(format!(
            "{}: rtl",
            app.label("app.terminal.textDirection.label")
        )));
    }
    panel = panel.push(
        scrollable(
            text(app.terminal.selected_output())
                .font(Font::MONOSPACE)
                .size(scaled_size(12.0, app.font_scale)),
        )
        .height(Length::Fill),
    );

    container(panel)
        .padding(10)
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}

fn tab_button<'a>(
    app: &'a IcedApp,
    index: usize,
    entry: &'a TerminalEntry,
) -> Element<'a, Message> {
    let label = format!(
        "{} {} [{}]",
        status_icon(entry.status),
        entry.title,
        app.label(status_label_key(entry.status))
    );
    button(text(label))
        .on_press(Message::TerminalSelect(index))
        .into()
}

fn tab_action_button<'a>(
    app: &'a IcedApp,
    index: usize,
    entry: &'a TerminalEntry,
) -> Element<'a, Message> {
    if !entry.closable {
        return text("").into();
    }
    let label = if entry.status == TerminalStatus::Running {
        app.label("app.terminal.cancelButton.title")
    } else {
        app.label("app.terminal.closeButton.title")
    };
    button(text(label))
        .on_press(Message::TerminalTabAction(index))
        .into()
}

fn terminal_status_detail(app: &IcedApp, entry: &TerminalEntry) -> Option<String> {
    if matches!(
        entry.status,
        TerminalStatus::Ready | TerminalStatus::Running | TerminalStatus::Ok
    ) {
        return None;
    }
    entry
        .output
        .lines()
        .find_map(|line| line.strip_prefix("[exit explanation] "))
        .map(|detail| format!("{}: {detail}", app.label(status_label_key(entry.status))))
        .or_else(|| Some(app.label(status_label_key(entry.status))))
}
