use crate::app_state::{AppState, LayoutDirection};
use crate::app_values::ensure_page;
use crate::{ui_page, ui_shared, ui_sidebar, ui_terminal};
use raylib::prelude::*;

const SIDEBAR_WIDTH: f32 = 280.0;
const GAP: f32 = 14.0;
const HIDDEN_TERMINAL_HEIGHT: f32 = 42.0;

pub fn draw(draw: &mut RaylibDrawHandle, state: &mut AppState) {
    draw.clear_background(ui_shared::BG);
    let width = draw.get_screen_width() as f32;
    let height = draw.get_screen_height() as f32;
    let terminal_height = if state.show_terminal {
        state
            .terminal_height
            .clamp(120.0, (height * 0.45).max(120.0))
    } else {
        HIDDEN_TERMINAL_HEIGHT
    };

    resize_terminal_from_mouse(draw, state, height);

    let sidebar = sidebar_rect(width, height, state.layout_direction);
    let content = content_rect(width, height, terminal_height, state.layout_direction);
    let terminal = terminal_rect(width, height, terminal_height, state.layout_direction);

    ui_sidebar::draw_sidebar(draw, sidebar, state);
    match ensure_page(state.current_page()) {
        Ok(page) => {
            ui_page::draw_page(draw, content, state, &page);
            ui_terminal::draw_terminal(draw, terminal, state);
        }
        Err(error) => {
            ui_shared::draw_panel(draw, content);
            draw.draw_text(
                &format!("{error:#}"),
                content.x as i32 + 16,
                content.y as i32 + 18,
                18,
                ui_shared::DANGER,
            );
        }
    }
    ui_terminal::draw_text_prompt(draw, state, width, height);
}

fn sidebar_rect(width: f32, height: f32, direction: LayoutDirection) -> Rectangle {
    let x = match direction {
        LayoutDirection::LeftToRight => GAP,
        LayoutDirection::RightToLeft => width - SIDEBAR_WIDTH - GAP,
    };
    Rectangle::new(x, GAP, SIDEBAR_WIDTH, (height - GAP * 2.0).max(0.0))
}

fn content_rect(
    width: f32,
    height: f32,
    terminal_height: f32,
    direction: LayoutDirection,
) -> Rectangle {
    let x = match direction {
        LayoutDirection::LeftToRight => SIDEBAR_WIDTH + GAP * 2.0,
        LayoutDirection::RightToLeft => GAP,
    };
    Rectangle::new(
        x,
        GAP,
        (width - SIDEBAR_WIDTH - GAP * 3.0).max(0.0),
        (height - terminal_height - GAP * 2.0).max(0.0),
    )
}

fn terminal_rect(
    width: f32,
    height: f32,
    terminal_height: f32,
    direction: LayoutDirection,
) -> Rectangle {
    let x = match direction {
        LayoutDirection::LeftToRight => SIDEBAR_WIDTH + GAP * 2.0,
        LayoutDirection::RightToLeft => GAP,
    };
    Rectangle::new(
        x,
        (height - terminal_height - GAP).max(0.0),
        (width - SIDEBAR_WIDTH - GAP * 3.0).max(0.0),
        terminal_height.max(0.0),
    )
}

fn resize_terminal_from_mouse(draw: &mut RaylibDrawHandle, state: &mut AppState, height: f32) {
    if !state.show_terminal {
        return;
    }
    let mouse = draw.get_mouse_position();
    let terminal_top = height - state.terminal_height - GAP;
    if draw.is_mouse_button_down(MouseButton::MOUSE_BUTTON_LEFT)
        && (mouse.y - terminal_top).abs() <= 8.0
    {
        state.terminal_height = (height - mouse.y - GAP).clamp(120.0, (height * 0.45).max(120.0));
    }
}
