use crate::app_state::LayoutDirection;
use crate::bundle::{ControlView, PageView};
use anyhow::{Result, anyhow};
use std::collections::BTreeMap;

pub fn control_value(control: &ControlView, values: &BTreeMap<String, String>) -> String {
    values
        .get(&control.id)
        .cloned()
        .unwrap_or_else(|| control.value.clone())
}

pub fn selected_option_title(control: &ControlView, value: &str) -> String {
    control
        .option_items
        .iter()
        .find(|option| option.id == value)
        .map(|option| option.title.clone())
        .unwrap_or_else(|| {
            if value.trim().is_empty() {
                "Select...".to_string()
            } else {
                value.to_string()
            }
        })
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

pub fn ensure_page(page: Option<PageView>) -> Result<PageView> {
    page.ok_or_else(|| anyhow!("bundle has no pages"))
}

pub fn layout_direction_for_locale(locale: &str) -> LayoutDirection {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn locale_direction_is_case_insensitive() {
        assert!(matches!(
            layout_direction_for_locale("AR"),
            LayoutDirection::RightToLeft
        ));
        assert!(matches!(
            layout_direction_for_locale("fa_IR"),
            LayoutDirection::RightToLeft
        ));
        assert!(matches!(
            layout_direction_for_locale("en-US"),
            LayoutDirection::LeftToRight
        ));
    }
}
