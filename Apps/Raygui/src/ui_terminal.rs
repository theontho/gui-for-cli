use crate::app_state::{AppState, TextDirection};
use crate::terminal::{TerminalStatus, status_label};
use crate::ui_shared::{self, BORDER, MUTED, TERMINAL_BG, TERMINAL_TEXT, TEXT};
use raylib::prelude::*;

pub fn draw_terminal(draw: &mut RaylibDrawHandle, bounds: Rectangle, state: &mut AppState) {
    draw.draw_rectangle_rec(bounds, TERMINAL_BG);
    draw.draw_rectangle_lines(
        bounds.x as i32,
        bounds.y as i32,
        bounds.width as i32,
        bounds.height as i32,
        BORDER,
    );
    draw_tabs(draw, bounds, state);
    if !state.show_terminal {
        return;
    }

    let output_bounds = Rectangle::new(
        bounds.x + 8.0,
        bounds.y + 42.0,
        bounds.width - 16.0,
        bounds.height - 50.0,
    );
    let output = state.terminal.selected_output().to_string();
    let content_height =
        ui_shared::estimate_text_height(&output, output_bounds.width - 26.0, 13) + 20.0;
    let content = Rectangle::new(
        output_bounds.x + 6.0,
        output_bounds.y + 6.0,
        output_bounds.width - 18.0,
        content_height,
    );
    let (_, view, scroll) = draw.gui_scroll_panel(
        output_bounds,
        "",
        content,
        state.terminal_scroll,
        Rectangle::new(0.0, 0.0, 0.0, 0.0),
    );
    state.terminal_scroll = scroll;
    let mut scoped = draw.begin_scissor_mode(
        view.x as i32,
        view.y as i32,
        view.width as i32,
        view.height as i32,
    );
    let output_x = match state.terminal_text_direction {
        TextDirection::LeftToRight => content.x,
        TextDirection::RightToLeft => content.x + 10.0,
    };
    ui_shared::draw_wrapped_text(
        &mut scoped,
        &output,
        output_x,
        content.y + state.terminal_scroll.y,
        content.width,
        13,
        TERMINAL_TEXT,
    );
}

pub fn draw_text_prompt(
    draw: &mut RaylibDrawHandle,
    state: &mut AppState,
    width: f32,
    height: f32,
) {
    let Some(prompt) = state.text_prompt.clone() else {
        return;
    };
    draw.draw_rectangle(0, 0, width as i32, height as i32, Color::new(0, 0, 0, 120));
    let bounds = Rectangle::new(width / 2.0 - 260.0, height / 2.0 - 95.0, 520.0, 190.0);
    ui_shared::draw_panel(draw, bounds);
    draw.draw_text(
        &prompt.label,
        (bounds.x + 18.0) as i32,
        (bounds.y + 18.0) as i32,
        20,
        TEXT,
    );
    draw.gui_panel(
        Rectangle::new(bounds.x + 18.0, bounds.y + 58.0, bounds.width - 36.0, 42.0),
        "",
    );
    draw.draw_text(
        &prompt.value,
        (bounds.x + 28.0) as i32,
        (bounds.y + 72.0) as i32,
        14,
        TEXT,
    );
    draw.draw_text(
        "Type a value, then press Enter or Save. Escape cancels.",
        (bounds.x + 18.0) as i32,
        (bounds.y + 110.0) as i32,
        12,
        MUTED,
    );
    if draw.gui_button(
        Rectangle::new(
            bounds.x + bounds.width - 180.0,
            bounds.y + 142.0,
            76.0,
            30.0,
        ),
        "Cancel",
    ) {
        state.text_prompt = None;
    }
    if draw.gui_button(
        Rectangle::new(bounds.x + bounds.width - 96.0, bounds.y + 142.0, 78.0, 30.0),
        "Save",
    ) {
        if let Some(prompt) = state.text_prompt.take() {
            state.update_field(&prompt.control_id, prompt.value);
        }
    }
}

fn draw_tabs(draw: &mut RaylibDrawHandle, bounds: Rectangle, state: &mut AppState) {
    let mut x = bounds.x + 8.0;
    let y = bounds.y + 8.0;
    let entries = state.terminal.entries().to_vec();
    for (index, entry) in entries.iter().enumerate() {
        let tab_width = (entry.title.len() as f32 * 8.0 + 72.0).clamp(96.0, 180.0);
        let label = format!("{} [{}]", entry.title, status_label(entry.status));
        if draw.gui_button(Rectangle::new(x, y, tab_width, 26.0), &label) {
            state.terminal.select(index);
        }
        x += tab_width + 4.0;
        if entry.closable {
            let action = if entry.status == TerminalStatus::Running {
                "Stop"
            } else {
                "X"
            };
            if draw.gui_button(Rectangle::new(x, y, 42.0, 26.0), action) {
                state.terminal_tab_action(index);
            }
            x += 46.0;
        }
    }
    let toggle = if state.show_terminal {
        "Hide terminal"
    } else {
        "Show terminal"
    };
    if draw.gui_button(
        Rectangle::new(bounds.x + bounds.width - 122.0, y, 112.0, 26.0),
        toggle,
    ) {
        state.show_terminal = !state.show_terminal;
    }
    draw.draw_text(
        "Drag edge or +/- resize",
        (bounds.x + bounds.width - 210.0) as i32,
        (y + 7.0) as i32,
        11,
        TERMINAL_TEXT,
    );
}
