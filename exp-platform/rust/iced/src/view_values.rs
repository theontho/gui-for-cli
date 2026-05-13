use crate::terminal::TerminalStatus;
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LayoutDirection {
    LeftToRight,
    RightToLeft,
}

pub fn layout_direction_for_locale(
    locale: &str,
    strings: &BTreeMap<String, String>,
) -> LayoutDirection {
    if strings
        .get("language.layoutDirection")
        .is_some_and(|value| value == "rtl")
    {
        return LayoutDirection::RightToLeft;
    }
    let language = locale
        .split(['-', '_'])
        .next()
        .unwrap_or(locale)
        .to_ascii_lowercase();
    if matches!(language.as_str(), "ar" | "fa" | "he" | "ur") {
        LayoutDirection::RightToLeft
    } else {
        LayoutDirection::LeftToRight
    }
}

pub fn scaled_size(base: f32, scale: f32) -> u16 {
    (base * scale).round().clamp(10.0, 34.0) as u16
}

pub fn status_icon(status: TerminalStatus) -> &'static str {
    match status {
        TerminalStatus::Ready => "•",
        TerminalStatus::Running => "◌",
        TerminalStatus::Ok => "✓",
        TerminalStatus::Warning => "!",
        TerminalStatus::Failed => "×",
    }
}

pub fn status_label_key(status: TerminalStatus) -> &'static str {
    match status {
        TerminalStatus::Ready => "app.setup.status.ready",
        TerminalStatus::Running => "app.setup.step.running",
        TerminalStatus::Ok => "app.setup.step.ok",
        TerminalStatus::Warning => "app.setup.step.warning",
        TerminalStatus::Failed => "app.setup.step.failed",
    }
}

pub fn checked_options(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(ToString::to_string)
        .collect()
}

pub fn set_checked_option(current: &str, option_id: &str, checked: bool) -> String {
    let mut values = checked_options(current);
    if checked {
        if !values.iter().any(|value| value == option_id) {
            values.push(option_id.to_string());
        }
    } else {
        values.retain(|value| value != option_id);
    }
    values.join(",")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn locale_direction_uses_strings_then_locale() {
        let rtl = BTreeMap::from([("language.layoutDirection".to_string(), "rtl".to_string())]);
        assert_eq!(
            layout_direction_for_locale("en", &rtl),
            LayoutDirection::RightToLeft
        );
        assert_eq!(
            layout_direction_for_locale("he-IL", &BTreeMap::new()),
            LayoutDirection::RightToLeft
        );
    }

    #[test]
    fn checkbox_values_are_stable() {
        assert_eq!(set_checked_option("a,b", "a", false), "b");
        assert_eq!(set_checked_option("a", "b", true), "a,b");
    }
}
