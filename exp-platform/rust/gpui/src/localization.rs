use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LayoutDirection {
    LeftToRight,
    RightToLeft,
}

pub fn layout_direction_for_locale(
    locale: &str,
    labels: &BTreeMap<String, String>,
) -> LayoutDirection {
    let declared = labels
        .get("language.direction")
        .map(|value| value.trim().to_ascii_lowercase());
    if declared.as_deref() == Some("rtl") || rtl_locale(locale) {
        LayoutDirection::RightToLeft
    } else {
        LayoutDirection::LeftToRight
    }
}

fn rtl_locale(locale: &str) -> bool {
    let language = locale
        .split(['-', '_'])
        .next()
        .unwrap_or(locale)
        .to_ascii_lowercase();
    matches!(language.as_str(), "ar" | "fa" | "he" | "iw" | "ur")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rtl_locale_uses_locale_and_string_hook() {
        assert_eq!(
            layout_direction_for_locale("ar", &BTreeMap::new()),
            LayoutDirection::RightToLeft
        );
        assert_eq!(
            layout_direction_for_locale(
                "en",
                &BTreeMap::from([("language.direction".to_string(), "rtl".to_string())])
            ),
            LayoutDirection::RightToLeft
        );
    }
}
