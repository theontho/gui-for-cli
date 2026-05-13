use crate::app::IcedApp;
use crate::messages::Message;
use crate::ui_controls;
use crate::ui_sidebar::sidebar;
use crate::ui_terminal::terminal_panel;
use iced::widget::{button, column, container, row, text};
use iced::{Alignment, Element, Length};

pub fn view(app: &IcedApp) -> Element<'_, Message> {
    let sidebar = if app.sidebar_visible {
        sidebar(app)
    } else {
        container(
            button(text(app.label("app.sidebar.show.label"))).on_press(Message::ToggleSidebar),
        )
        .padding(12)
        .width(Length::Shrink)
        .into()
    };
    let detail = detail(app);

    let shell = if app.is_rtl() {
        row![detail, sidebar]
    } else {
        row![sidebar, detail]
    }
    .spacing(12)
    .height(Length::Fill)
    .width(Length::Fill);

    container(shell).padding(12).into()
}

fn detail(app: &IcedApp) -> Element<'_, Message> {
    let page = app
        .current_page()
        .map(|page| ui_controls::page_content(app, page))
        .unwrap_or_else(|| text(app.label("app.page.empty.title")).into());
    let terminal_height = if app.terminal_visible {
        Length::Fixed(app.terminal_height)
    } else {
        Length::Shrink
    };

    let detail = column![
        container(page).height(Length::Fill).width(Length::Fill),
        container(terminal_panel(app))
            .height(terminal_height)
            .width(Length::Fill)
    ]
    .spacing(8)
    .align_x(Alignment::Start)
    .width(Length::Fill)
    .height(Length::Fill);

    container(detail)
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}
