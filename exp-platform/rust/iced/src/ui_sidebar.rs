use crate::app::IcedApp;
use crate::control_text::setup_command_preview;
use crate::messages::Message;
use crate::terminal::TerminalStatus;
use crate::view_values::{scaled_size, status_icon, status_label_key};
use iced::widget::{button, column, container, horizontal_rule, row, scrollable, slider, text};
use iced::{Alignment, Element, Length};

pub fn sidebar(app: &IcedApp) -> Element<'_, Message> {
    let mut content = column![
        row![
            text(&app.title).size(scaled_size(24.0, app.font_scale)),
            button(text(app.label("app.sidebar.hide.label"))).on_press(Message::ToggleSidebar),
        ]
        .spacing(8)
        .align_y(Alignment::Center),
    ]
    .spacing(10)
    .width(Length::Fill);

    if !app.summary.is_empty() {
        content = content.push(text(&app.summary).size(scaled_size(13.0, app.font_scale)));
    }
    content = content
        .push(horizontal_rule(1))
        .push(setup_section(app))
        .push(horizontal_rule(1))
        .push(standard_options(app))
        .push(horizontal_rule(1))
        .push(page_list(app));

    container(scrollable(content).height(Length::Fill))
        .padding(14)
        .width(Length::Fixed(290.0))
        .height(Length::Fill)
        .into()
}

fn setup_section(app: &IcedApp) -> Element<'_, Message> {
    let mut section = column![
        text(app.label("app.setup.status.title")).size(scaled_size(16.0, app.font_scale)),
        text(setup_status(app)).size(scaled_size(12.0, app.font_scale)),
    ]
    .spacing(8);

    for line in &app.setup_lines {
        section = section.push(text(line).size(scaled_size(12.0, app.font_scale)));
    }
    for (index, step) in app.setup_steps.iter().enumerate() {
        let running = app.running_setup_indexes.contains(&index);
        let label = if running {
            format!("{} {}", status_icon(TerminalStatus::Running), step.label)
        } else {
            format!("{}: {}", app.label("app.setup.runButton.title"), step.label)
        };
        let mut run_button = button(text(label));
        if !running {
            run_button = run_button.on_press(Message::RunSetup(index));
        }
        section = section.push(
            column![
                run_button,
                text(setup_command_preview(step)).size(scaled_size(11.0, app.font_scale))
            ]
            .spacing(3),
        );
    }
    section.into()
}

fn setup_status(app: &IcedApp) -> String {
    if app.setup_steps.is_empty() {
        return app.label("app.setup.status.none");
    }
    if app
        .terminal
        .entries()
        .iter()
        .any(|entry| entry.status == TerminalStatus::Running)
    {
        return app.label(status_label_key(TerminalStatus::Running));
    }
    app.label("app.setup.status.ready")
}

fn standard_options(app: &IcedApp) -> Element<'_, Message> {
    let terminal_height = slider(
        120.0..=430.0,
        app.terminal_height,
        Message::SetTerminalHeight,
    );
    let font_scale = slider(0.8..=1.6, app.font_scale, Message::SetFontScale);
    column![
        text(app.label("app.standardOptions.title")).size(scaled_size(16.0, app.font_scale)),
        text(format!(
            "{}: {}",
            app.label("language.setting.label"),
            app.label("language.name")
        )),
        text(format!(
            "{}: {:?} / {}: {}",
            app.label("app.layoutDirection.label"),
            app.layout_direction,
            app.label("app.terminal.textDirection.label"),
            app.terminal_text_direction
        )),
        text(app.label("app.fontSize.label")),
        font_scale,
        text(app.label("app.terminal.commandOutput.label")),
        terminal_height,
        button(text(app.label("app.workspace.openButton.title"))).on_press(Message::OpenWorkspace),
    ]
    .spacing(8)
    .into()
}

fn page_list(app: &IcedApp) -> Element<'_, Message> {
    let mut pages = column![].spacing(5);
    let mut last_group = String::new();
    for (index, page) in app.pages.iter().enumerate() {
        let group = app.page_group(page);
        if !group.is_empty() && group != last_group {
            pages = pages.push(text(group.clone()).size(scaled_size(12.0, app.font_scale)));
            last_group = group;
        }
        let marker = if index == app.selected_page {
            "▸"
        } else {
            " "
        };
        pages = pages.push(
            button(text(format!("{marker} {}", page.title))).on_press(Message::SelectPage(index)),
        );
    }
    pages.into()
}
