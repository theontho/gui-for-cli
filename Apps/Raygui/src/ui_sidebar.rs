use crate::app_state::{AppState, LayoutDirection};
use crate::ui_shared::{self, MUTED, PADDING, TEXT};
use raylib::prelude::*;

pub fn draw_sidebar(draw: &mut RaylibDrawHandle, bounds: Rectangle, state: &mut AppState) {
    ui_shared::draw_panel(draw, bounds);
    let mut y = bounds.y + PADDING;
    draw.draw_text(
        &state.title,
        (bounds.x + PADDING) as i32,
        y as i32,
        22,
        TEXT,
    );
    y += 32.0;
    y += ui_shared::draw_wrapped_text(
        draw,
        &state.summary,
        bounds.x + PADDING,
        y,
        bounds.width - PADDING * 2.0,
        14,
        MUTED,
    );
    y += 8.0;
    draw_metadata(draw, bounds, state, &mut y);
    draw_setup(draw, bounds, state, &mut y);
    draw_pages(draw, bounds, state, y + 10.0);
}

fn draw_metadata(
    draw: &mut RaylibDrawHandle,
    bounds: Rectangle,
    state: &mut AppState,
    y: &mut f32,
) {
    draw.draw_text(
        &format!(
            "Locale {} / layout {} / terminal {}",
            state.locale,
            match state.layout_direction {
                LayoutDirection::LeftToRight => "LTR",
                LayoutDirection::RightToLeft => "RTL",
            },
            match state.terminal_text_direction {
                crate::app_state::TextDirection::LeftToRight => "LTR",
                crate::app_state::TextDirection::RightToLeft => "RTL",
            }
        ),
        (bounds.x + PADDING) as i32,
        *y as i32,
        11,
        MUTED,
    );
    *y += 18.0;
    draw.draw_text(
        &format!("Loaded in {:.1} ms", state.loaded_ms),
        (bounds.x + PADDING) as i32,
        *y as i32,
        11,
        MUTED,
    );
    *y += 18.0;
    draw.draw_text(
        &format!(
            "{} controls / {} actions / {} data sources",
            state.control_count, state.action_count, state.data_source_count
        ),
        (bounds.x + PADDING) as i32,
        *y as i32,
        11,
        MUTED,
    );
    *y += 20.0;
    if draw.gui_button(
        Rectangle::new(bounds.x + PADDING, *y, bounds.width - PADDING * 2.0, 28.0),
        "Open workspace",
    ) {
        state.open_workspace();
    }
    *y += 38.0;
}

fn draw_setup(draw: &mut RaylibDrawHandle, bounds: Rectangle, state: &mut AppState, y: &mut f32) {
    draw.draw_text("Setup", (bounds.x + PADDING) as i32, *y as i32, 16, TEXT);
    *y += 24.0;
    *y += ui_shared::draw_wrapped_text(
        draw,
        &state.setup_status_summary(),
        bounds.x + PADDING,
        *y,
        bounds.width - PADDING * 2.0,
        12,
        MUTED,
    );
    *y += 8.0;
    let previews = state.setup_previews();
    for index in 0..state.setup_steps.len() {
        let label = state.setup_steps[index].label.clone();
        if draw.gui_button(
            Rectangle::new(bounds.x + PADDING, *y, bounds.width - PADDING * 2.0, 28.0),
            &label,
        ) {
            state.run_setup(index);
        }
        *y += 32.0;
        *y += ui_shared::draw_wrapped_text(
            draw,
            &previews[index],
            bounds.x + PADDING,
            *y,
            bounds.width - PADDING * 2.0,
            11,
            MUTED,
        );
        *y += 8.0;
    }
    if state.setup_steps.is_empty() && !state.setup_lines.is_empty() {
        *y += ui_shared::draw_wrapped_text(
            draw,
            &state.setup_lines.join("\n"),
            bounds.x + PADDING,
            *y,
            bounds.width - PADDING * 2.0,
            11,
            MUTED,
        );
    }
    draw.draw_rectangle(
        (bounds.x + PADDING) as i32,
        *y as i32,
        (bounds.width - PADDING * 2.0) as i32,
        1,
        ui_shared::BORDER,
    );
}

fn draw_pages(draw: &mut RaylibDrawHandle, bounds: Rectangle, state: &mut AppState, y: f32) {
    let panel = Rectangle::new(
        bounds.x + PADDING,
        y,
        bounds.width - PADDING * 2.0,
        bounds.y + bounds.height - y - PADDING,
    );
    let content_height = 34.0 + state.pages.len() as f32 * 36.0 + group_count(state) as f32 * 24.0;
    let content = Rectangle::new(
        panel.x + 4.0,
        panel.y + 4.0,
        panel.width - 18.0,
        content_height,
    );
    let (_, view, scroll) = draw.gui_scroll_panel(
        panel,
        "",
        content,
        state.sidebar_scroll,
        Rectangle::new(0.0, 0.0, 0.0, 0.0),
    );
    state.sidebar_scroll = scroll;
    let mut scoped = draw.begin_scissor_mode(
        view.x as i32,
        view.y as i32,
        view.width as i32,
        view.height as i32,
    );
    let mut current_y = content.y + state.sidebar_scroll.y;
    scoped.draw_text("Pages", content.x as i32, current_y as i32, 16, TEXT);
    current_y += 28.0;
    let mut current_group = String::new();
    for index in 0..state.pages.len() {
        let group = state.page_group(&state.pages[index]);
        if group != current_group {
            current_group = group.clone();
            if !group.trim().is_empty() {
                scoped.draw_text(&group, content.x as i32, current_y as i32, 11, MUTED);
                current_y += 18.0;
            }
        }
        let label = state.pages[index].title.clone();
        if index == state.selected_page {
            scoped.draw_rectangle_rec(
                Rectangle::new(content.x, current_y, content.width - 4.0, 30.0),
                ui_shared::PANEL_SUBTLE,
            );
        }
        if scoped.gui_button(
            Rectangle::new(content.x, current_y, content.width - 4.0, 30.0),
            &label,
        ) {
            state.select_page(index);
        }
        current_y += 34.0;
    }
}

fn group_count(state: &AppState) -> usize {
    let mut groups = Vec::<String>::new();
    for page in &state.pages {
        let group = state.page_group(page);
        if !group.trim().is_empty() && !groups.contains(&group) {
            groups.push(group);
        }
    }
    groups.len()
}
