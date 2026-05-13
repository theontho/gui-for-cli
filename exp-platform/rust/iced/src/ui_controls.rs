use crate::app::IcedApp;
use crate::bundle::{ActionView, ControlView, PageView};
use crate::data_view::{ControlDataRows, control_data_rows};
use crate::execution::{action_preview, action_unavailable_reason};
use crate::messages::Message;
use crate::row_actions::{DataSourceRowActionView, DataSourceRowView};
use crate::view_values::{scaled_size, set_checked_option};
use iced::widget::{
    button, checkbox, column, container, horizontal_rule, pick_list, row, scrollable, text,
    text_input,
};
use iced::{Alignment, Element, Length};
use std::collections::BTreeMap;

pub fn page_content<'a>(app: &'a IcedApp, page: &'a PageView) -> Element<'a, Message> {
    let mut content = column![
        text(&page.title).size(scaled_size(26.0, app.font_scale)),
        text(&page.summary).size(scaled_size(14.0, app.font_scale)),
        horizontal_rule(1),
    ]
    .spacing(10)
    .width(Length::Fill);

    if !page.body.is_empty() {
        content = content.push(body_text(app, &page.body));
    }
    for control in &page.controls {
        content = content.push(control_card(app, control));
    }

    let values = app.effective_field_values(page);
    let actions = app.visible_actions(page, &values);
    if !actions.is_empty() {
        content = content.push(horizontal_rule(1)).push(
            text(app.label("app.actionsColumn.title")).size(scaled_size(18.0, app.font_scale)),
        );
        for action in actions {
            content = content.push(action_view(app, action, &values));
        }
    }

    scrollable(container(content).padding(14).width(Length::Fill))
        .height(Length::Fill)
        .into()
}

fn body_text<'a>(app: &'a IcedApp, body: &'a str) -> Element<'a, Message> {
    let mut lines = column![].spacing(5);
    for line in body.lines() {
        if line.trim().is_empty() {
            continue;
        }
        if let Some(heading) = line.strip_prefix("## ") {
            lines = lines.push(text(heading.to_string()).size(scaled_size(17.0, app.font_scale)));
        } else {
            lines = lines.push(text(line.to_string()).size(scaled_size(13.0, app.font_scale)));
        }
    }
    lines.into()
}

fn control_card<'a>(app: &'a IcedApp, control: &'a ControlView) -> Element<'a, Message> {
    let mut card = column![
        text(&control.label).size(scaled_size(16.0, app.font_scale)),
        control_widget(app, control),
    ]
    .spacing(8)
    .width(Length::Fill);

    if !control.helper.is_empty() {
        card = card.push(text(&control.helper).size(scaled_size(12.0, app.font_scale)));
    }
    if matches!(control.kind.as_str(), "infoGrid" | "libraryList") {
        card = card.push(data_rows(app, control));
    } else {
        let details = app.control_details(control);
        if !details.is_empty() {
            card = card.push(text(details).size(scaled_size(12.0, app.font_scale)));
        }
    }

    container(card).padding(12).width(Length::Fill).into()
}

fn control_widget<'a>(app: &'a IcedApp, control: &'a ControlView) -> Element<'a, Message> {
    let value = app.control_value(control);
    match control.kind.as_str() {
        "toggle" => checkbox(control.label.clone(), value == "true")
            .on_toggle({
                let id = control.id.clone();
                move |checked| Message::ControlChanged(id.clone(), checked.to_string())
            })
            .into(),
        "dropdown" if !control.option_items.is_empty() => dropdown(app, control, &value),
        "checkboxGroup" if !control.option_items.is_empty() => checkbox_group(app, control, &value),
        "path" => path_input(app, control, &value),
        "text" => text_like(control, &value),
        _ => text(value).into(),
    }
}

fn dropdown<'a>(app: &'a IcedApp, control: &'a ControlView, value: &str) -> Element<'a, Message> {
    let choices = control
        .option_items
        .iter()
        .map(|option| option.title.clone())
        .collect::<Vec<_>>();
    let selected = control
        .option_items
        .iter()
        .find(|option| option.id == value)
        .map(|option| option.title.clone());
    let pairs = control
        .option_items
        .iter()
        .map(|option| (option.title.clone(), option.id.clone()))
        .collect::<Vec<_>>();
    let id = control.id.clone();
    column![
        pick_list(choices, selected, move |title| {
            let selected_id = pairs
                .iter()
                .find(|(candidate, _)| candidate == &title)
                .map(|(_, id)| id.clone())
                .unwrap_or(title);
            Message::ControlChanged(id.clone(), selected_id)
        }),
        text(app.label("app.control.chooseValue")).size(scaled_size(11.0, app.font_scale)),
    ]
    .spacing(4)
    .into()
}

fn checkbox_group<'a>(
    app: &'a IcedApp,
    control: &'a ControlView,
    value: &str,
) -> Element<'a, Message> {
    let mut group = column![].spacing(4);
    for option in &control.option_items {
        let current = value.to_string();
        let id = control.id.clone();
        let option_id = option.id.clone();
        let checked = current
            .split(',')
            .map(str::trim)
            .any(|item| item == option.id);
        group = group.push(
            checkbox(option.title.clone(), checked).on_toggle(move |next| {
                Message::ControlChanged(id.clone(), set_checked_option(&current, &option_id, next))
            }),
        );
    }
    text_sized_container(group.into(), app)
}

fn path_input<'a>(app: &'a IcedApp, control: &'a ControlView, value: &str) -> Element<'a, Message> {
    let id = control.id.clone();
    let placeholder = control.placeholder.clone();
    row![
        text_input(&placeholder, value).on_input({
            let id = id.clone();
            move |value| Message::ControlChanged(id.clone(), value)
        }),
        button(text(app.label("app.pathPicker.chooseButton.title")))
            .on_press(Message::PickPath(id)),
    ]
    .spacing(8)
    .align_y(Alignment::Center)
    .into()
}

fn text_like<'a>(control: &'a ControlView, value: &str) -> Element<'a, Message> {
    let id = control.id.clone();
    text_input(&control.placeholder, value)
        .on_input(move |value| Message::ControlChanged(id.clone(), value))
        .into()
}

fn data_rows<'a>(app: &'a IcedApp, control: &'a ControlView) -> Element<'a, Message> {
    let values = app.field_values.clone();
    let rows = control_data_rows(
        control,
        &values,
        &mut app.data_source_cache.borrow_mut(),
        &app.bundle_root,
    );
    match rows {
        ControlDataRows::Rows(rows) => row_list(app, control, rows, &values),
        ControlDataRows::Empty => text(app.label("app.library.empty")).into(),
        ControlDataRows::Error(error) => text(format!(
            "{}: {error}",
            app.label("app.dataSource.error.title")
        ))
        .into(),
    }
}

fn row_list<'a>(
    app: &'a IcedApp,
    control: &'a ControlView,
    rows: Vec<DataSourceRowView>,
    values: &BTreeMap<String, String>,
) -> Element<'a, Message> {
    let mut list = column![].spacing(8);
    for row_data in rows {
        let mut row_content =
            column![text(row_data.label.clone()).size(scaled_size(14.0, app.font_scale))]
                .spacing(4);
        let columns = control
            .columns
            .iter()
            .filter_map(|column| {
                row_data
                    .values
                    .get(&column.id)
                    .map(|value| (&column.title, value))
            })
            .map(|(title, value)| format!("{title}: {value}"))
            .collect::<Vec<_>>()
            .join("  •  ");
        if !columns.is_empty() {
            row_content = row_content.push(text(columns));
        }
        let meta = [status_text(app, &row_data.status), row_data.tags.join(", ")]
            .into_iter()
            .filter(|item| !item.trim().is_empty())
            .collect::<Vec<_>>()
            .join("  •  ");
        if !meta.is_empty() {
            row_content = row_content.push(text(meta).size(scaled_size(12.0, app.font_scale)));
        }
        if !row_data.actions.is_empty() {
            row_content = row_content.push(row_actions(app, row_data.actions, values));
        }
        list = list.push(container(row_content).padding(8).width(Length::Fill));
    }
    list.into()
}

fn row_actions<'a>(
    app: &'a IcedApp,
    actions: Vec<DataSourceRowActionView>,
    values: &BTreeMap<String, String>,
) -> Element<'a, Message> {
    let mut buttons = row![].spacing(6).align_y(Alignment::Center);
    for row_action in actions {
        buttons = buttons.push(action_button(
            app,
            row_action.action,
            values,
            row_action.disabled_reason,
        ));
    }
    buttons.into()
}

fn action_view<'a>(
    app: &'a IcedApp,
    action: ActionView,
    values: &BTreeMap<String, String>,
) -> Element<'a, Message> {
    let detail = app
        .action_disabled_reason(&action, values)
        .unwrap_or_else(|| action_preview(&action, values));
    column![
        action_button(app, action, values, None),
        text(detail).size(scaled_size(12.0, app.font_scale))
    ]
    .spacing(3)
    .into()
}

fn action_button<'a>(
    app: &'a IcedApp,
    action: ActionView,
    values: &BTreeMap<String, String>,
    disabled_reason: Option<String>,
) -> Element<'a, Message> {
    let running = app.action_is_running(&action);
    let unavailable = disabled_reason.or_else(|| action_unavailable_reason(&action, values));
    let enabled = unavailable.is_none() && !running;
    let label = if running {
        format!("◌ {}", action.title)
    } else {
        action.title.clone()
    };
    let mut control = button(text(label));
    if action.role == "destructive" {
        control = control.style(button::danger);
    }
    if enabled {
        control = control.on_press(Message::RunAction(action));
    }
    control.into()
}

fn status_text(app: &IcedApp, status: &str) -> String {
    if status.is_empty() {
        return String::new();
    }
    app.labels
        .get(&format!("library.status.{status}"))
        .cloned()
        .unwrap_or_else(|| status.to_string())
}

fn text_sized_container<'a>(content: Element<'a, Message>, app: &IcedApp) -> Element<'a, Message> {
    container(column![content].spacing(scaled_size(2.0, app.font_scale))).into()
}
