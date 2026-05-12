use crate::bundle::ControlView;
use raylib::prelude::*;
use std::ffi::CString;

pub const PADDING: f32 = 16.0;
pub const LINE: f32 = 20.0;

pub const BG: Color = Color::new(246, 247, 251, 255);
pub const PANEL: Color = Color::new(255, 255, 255, 255);
pub const PANEL_SUBTLE: Color = Color::new(248, 249, 252, 255);
pub const BORDER: Color = Color::new(215, 219, 231, 255);
pub const TEXT: Color = Color::new(28, 35, 51, 255);
pub const MUTED: Color = Color::new(86, 96, 112, 255);
pub const DANGER: Color = Color::new(138, 81, 96, 255);
pub const TERMINAL_BG: Color = Color::new(31, 36, 48, 255);
pub const TERMINAL_TEXT: Color = Color::new(230, 235, 244, 255);

pub fn draw_panel<D: RaylibDraw>(draw: &mut D, bounds: Rectangle) {
    draw.draw_rectangle_rec(bounds, PANEL);
    draw.draw_rectangle_lines(
        bounds.x as i32,
        bounds.y as i32,
        bounds.width as i32,
        bounds.height as i32,
        BORDER,
    );
}

pub fn control_height(control: &ControlView) -> f32 {
    match control.kind.as_str() {
        "libraryList" => 260.0,
        "infoGrid" => 176.0,
        "checkboxGroup" => 174.0,
        "toggle" => 118.0,
        _ => 132.0,
    }
}

pub fn estimate_text_height(text: &str, width: f32, font_size: i32) -> f32 {
    let mut height = 0.0;
    for paragraph in text.lines() {
        if paragraph.trim().is_empty() {
            height += LINE * 0.6;
            continue;
        }
        let mut line = String::new();
        for word in paragraph.split_whitespace() {
            let candidate = if line.is_empty() {
                word.to_string()
            } else {
                format!("{line} {word}")
            };
            if measure_text_width(&candidate, font_size) > width && !line.is_empty() {
                height += font_size as f32 + 6.0;
                line = word.to_string();
            } else {
                line = candidate;
            }
        }
        height += font_size as f32 + 6.0;
    }
    height
}

pub fn draw_wrapped_text<D: RaylibDraw>(
    draw: &mut D,
    text: &str,
    x: f32,
    y: f32,
    width: f32,
    font_size: i32,
    color: Color,
) -> f32 {
    let mut current_y = y;
    for paragraph in text.lines() {
        if paragraph.trim().is_empty() {
            current_y += LINE * 0.6;
            continue;
        }
        let mut line = String::new();
        for word in paragraph.split_whitespace() {
            let candidate = if line.is_empty() {
                word.to_string()
            } else {
                format!("{line} {word}")
            };
            if measure_text_width(&candidate, font_size) > width && !line.is_empty() {
                draw.draw_text(&line, x as i32, current_y as i32, font_size, color);
                current_y += font_size as f32 + 6.0;
                line = word.to_string();
            } else {
                line = candidate;
            }
        }
        if !line.is_empty() {
            draw.draw_text(&line, x as i32, current_y as i32, font_size, color);
            current_y += font_size as f32 + 6.0;
        }
    }
    current_y - y
}

fn measure_text_width(text: &str, font_size: i32) -> f32 {
    let text = CString::new(text).unwrap_or_default();
    unsafe { raylib::ffi::MeasureText(text.as_ptr(), font_size) as f32 }
}
