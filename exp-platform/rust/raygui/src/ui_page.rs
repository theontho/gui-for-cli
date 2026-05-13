use crate::app_state::{ActionSummary, AppState};
use crate::app_values::{
    checked_options, control_value, selected_option_title, set_checked_option,
};
use crate::bundle::{ControlView, PageView};
use crate::control_text::control_options;
use crate::ui_shared::{self, BORDER, DANGER, MUTED, PANEL_SUBTLE, TEXT};
use raylib::prelude::*;

pub fn draw_page(
    draw: &mut RaylibDrawHandle,
    bounds: Rectangle,
    state: &mut AppState,
    page: &PageView,
) {
    ui_shared::draw_panel(draw, bounds);
    let body_height = estimate_page_height(page, state, bounds.width - 52.0);
    let content = Rectangle::new(
        bounds.x + 12.0,
        bounds.y + 12.0,
        bounds.width - 28.0,
        body_height,
    );
    let (_, view, scroll) = draw.gui_scroll_panel(
        bounds,
        "",
        content,
        state.content_scroll,
        Rectangle::new(0.0, 0.0, 0.0, 0.0),
    );
    state.content_scroll = scroll;

    let mut scoped = draw.begin_scissor_mode(
        view.x as i32,
        view.y as i32,
        view.width as i32,
        view.height as i32,
    );
    let mut y = content.y + state.content_scroll.y;
    scoped.draw_text(&page.title, content.x as i32 + 8, y as i32, 26, TEXT);
    y += 36.0;
    y += ui_shared::draw_wrapped_text(
        &mut scoped,
        &page.summary,
        content.x + 8.0,
        y,
        content.width - 16.0,
        15,
        MUTED,
    );
    y += 12.0;
    scoped.draw_rectangle(
        (content.x + 8.0) as i32,
        y as i32,
        (content.width - 16.0) as i32,
        1,
        BORDER,
    );
    y += 14.0;
    y += ui_shared::draw_wrapped_text(
        &mut scoped,
        &page.body,
        content.x + 8.0,
        y,
        content.width - 16.0,
        14,
        TEXT,
    );
    y += 16.0;

    for control in &page.controls {
        y = draw_control(
            &mut scoped,
            state,
            control,
            content.x + 8.0,
            y,
            content.width - 16.0,
        );
        y += 10.0;
    }

    let actions = state.action_summaries(page);
    if !actions.is_empty() {
        scoped.draw_text("Actions", content.x as i32 + 8, y as i32, 18, TEXT);
        y += 28.0;
        for (index, action) in actions.iter().enumerate() {
            y = draw_action(
                &mut scoped,
                state,
                page,
                index,
                action,
                content.x + 8.0,
                y,
                content.width - 16.0,
            );
            y += 8.0;
        }
    }
}

fn draw_control(
    draw: &mut RaylibScissorMode<RaylibDrawHandle>,
    state: &mut AppState,
    control: &ControlView,
    x: f32,
    y: f32,
    width: f32,
) -> f32 {
    let height = ui_shared::control_height(control);
    let bounds = Rectangle::new(x, y, width, height);
    draw.draw_rectangle_rec(bounds, PANEL_SUBTLE);
    draw.draw_rectangle_lines(
        bounds.x as i32,
        bounds.y as i32,
        bounds.width as i32,
        bounds.height as i32,
        BORDER,
    );
    draw.draw_text(
        &control.label,
        (x + 10.0) as i32,
        (y + 9.0) as i32,
        15,
        TEXT,
    );

    let value = control_value(control, &state.field_values);
    let input_y = y + 34.0;
    match control.kind.as_str() {
        "toggle" => draw_toggle(draw, state, control, &value, x, input_y),
        "dropdown" => draw_dropdown(draw, state, control, &value, x, input_y, width),
        "checkboxGroup" => draw_checkbox_group(draw, state, control, &value, x, input_y, width),
        "text" | "path" => draw_text_like_control(draw, state, control, &value, x, input_y, width),
        _ => draw_read_only_control(draw, control, &value, x, input_y, width),
    }

    let helper = {
        let mut cache = state.data_source_cache.borrow_mut();
        control_options(control, &state.field_values, &mut cache, &state.bundle_root)
    };
    let helper_text = [control.helper.as_str(), helper.as_str()]
        .into_iter()
        .filter(|value| !value.trim().is_empty())
        .collect::<Vec<_>>()
        .join("\n");
    if !helper_text.is_empty() {
        ui_shared::draw_wrapped_text(
            draw,
            &helper_text,
            x + 10.0,
            y + height - 42.0,
            width - 20.0,
            12,
            MUTED,
        );
    }

    y + height
}

fn draw_toggle(
    draw: &mut RaylibScissorMode<RaylibDrawHandle>,
    state: &mut AppState,
    control: &ControlView,
    value: &str,
    x: f32,
    y: f32,
) {
    let mut checked = value == "true";
    let before = checked;
    draw.gui_check_box(
        Rectangle::new(x + 10.0, y, 22.0, 22.0),
        "Enabled",
        &mut checked,
    );
    if checked != before {
        state.update_field(&control.id, checked.to_string());
    }
}

fn draw_dropdown(
    draw: &mut RaylibScissorMode<RaylibDrawHandle>,
    state: &mut AppState,
    control: &ControlView,
    value: &str,
    x: f32,
    y: f32,
    width: f32,
) {
    let text = if control.option_items.is_empty() {
        control.options.clone()
    } else {
        control
            .option_items
            .iter()
            .map(|option| option.title.as_str())
            .collect::<Vec<_>>()
            .join(";")
    };
    let mut active = control
        .option_items
        .iter()
        .position(|option| option.id == value)
        .unwrap_or(0) as i32;
    let before = active;
    draw.gui_combo_box(
        Rectangle::new(x + 10.0, y, width - 20.0, 28.0),
        &text,
        &mut active,
    );
    if active != before {
        if let Some(option) = control.option_items.get(active.max(0) as usize) {
            state.update_field(&control.id, option.id.clone());
        }
    }
    draw.draw_text(
        &selected_option_title(control, value),
        (x + 14.0) as i32,
        (y + 34.0) as i32,
        12,
        MUTED,
    );
}

fn draw_checkbox_group(
    draw: &mut RaylibScissorMode<RaylibDrawHandle>,
    state: &mut AppState,
    control: &ControlView,
    value: &str,
    x: f32,
    y: f32,
    width: f32,
) {
    let selected = checked_options(value);
    let mut current_y = y;
    for option in &control.option_items {
        let mut checked = selected.iter().any(|id| id == &option.id);
        let before = checked;
        draw.gui_check_box(
            Rectangle::new(x + 10.0, current_y, width - 20.0, 22.0),
            &option.title,
            &mut checked,
        );
        if checked != before {
            state.update_field(&control.id, set_checked_option(value, &option.id, checked));
        }
        current_y += 25.0;
    }
}

fn draw_text_like_control(
    draw: &mut RaylibScissorMode<RaylibDrawHandle>,
    state: &mut AppState,
    control: &ControlView,
    value: &str,
    x: f32,
    y: f32,
    width: f32,
) {
    draw.gui_panel(Rectangle::new(x + 10.0, y, width - 118.0, 28.0), "");
    let display = if value.trim().is_empty() {
        control.placeholder.as_str()
    } else {
        value
    };
    draw.draw_text(display, (x + 18.0) as i32, (y + 8.0) as i32, 12, MUTED);
    if draw.gui_button(Rectangle::new(x + width - 98.0, y, 40.0, 28.0), "Edit") {
        state.open_text_prompt(control);
    }
    if control.kind == "path"
        && draw.gui_button(Rectangle::new(x + width - 54.0, y, 44.0, 28.0), "Pick")
    {
        state.pick_path_for(control);
    }
}

fn draw_read_only_control(
    draw: &mut RaylibScissorMode<RaylibDrawHandle>,
    control: &ControlView,
    value: &str,
    x: f32,
    y: f32,
    width: f32,
) {
    let text = if control.options.is_empty() {
        value
    } else {
        control.options.as_str()
    };
    ui_shared::draw_wrapped_text(draw, text, x + 10.0, y, width - 20.0, 12, MUTED);
}

fn draw_action(
    draw: &mut RaylibScissorMode<RaylibDrawHandle>,
    state: &mut AppState,
    page: &PageView,
    index: usize,
    action: &ActionSummary,
    x: f32,
    y: f32,
    width: f32,
) -> f32 {
    let bounds = Rectangle::new(x, y, width, 64.0);
    draw.draw_rectangle_rec(bounds, PANEL_SUBTLE);
    draw.draw_rectangle_lines(
        bounds.x as i32,
        bounds.y as i32,
        bounds.width as i32,
        bounds.height as i32,
        BORDER,
    );
    if !action.enabled {
        draw.gui_disable();
    }
    if draw.gui_button(
        Rectangle::new(x + 10.0, y + 10.0, 170.0, 28.0),
        &action.title,
    ) {
        state.run_action(page, index);
    }
    if !action.enabled {
        draw.gui_enable();
    }
    ui_shared::draw_wrapped_text(
        draw,
        &action.preview,
        x + 190.0,
        y + 12.0,
        width - 200.0,
        11,
        if action.enabled { MUTED } else { DANGER },
    );
    y + 64.0
}

fn estimate_page_height(page: &PageView, state: &AppState, width: f32) -> f32 {
    let actions = state.action_summaries(page);
    80.0 + ui_shared::estimate_text_height(&page.summary, width, 15)
        + ui_shared::estimate_text_height(&page.body, width, 14)
        + page
            .controls
            .iter()
            .map(ui_shared::control_height)
            .sum::<f32>()
        + page.controls.len() as f32 * 12.0
        + if actions.is_empty() {
            0.0
        } else {
            34.0 + actions.len() as f32 * 72.0
        }
        + 80.0
}
