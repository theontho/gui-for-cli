use serde::Deserialize;
use std::collections::BTreeMap;

#[derive(Debug, Clone, Deserialize)]
pub struct ExitCodeReference {
    pub code: i32,
    pub title: String,
    pub summary: String,
    #[serde(default)]
    pub severity: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ExitCodeReferenceView {
    pub title: String,
    pub summary: String,
    pub severity: String,
}

pub struct ExitExplanation {
    pub title: String,
    pub summary: String,
    pub severity: String,
}

pub fn effective_exit_code_reference(
    overrides: &[ExitCodeReference],
    strings: &BTreeMap<String, String>,
) -> BTreeMap<i32, ExitCodeReferenceView> {
    let mut references = BTreeMap::from([
        (
            1,
            exit_code_reference_view(
                1,
                "exitCodes.default.1.title",
                "exitCodes.default.1.summary",
                "error",
                strings,
            ),
        ),
        (
            2,
            exit_code_reference_view(
                2,
                "exitCodes.default.2.title",
                "exitCodes.default.2.summary",
                "error",
                strings,
            ),
        ),
        (
            126,
            exit_code_reference_view(
                126,
                "exitCodes.default.126.title",
                "exitCodes.default.126.summary",
                "error",
                strings,
            ),
        ),
        (
            127,
            exit_code_reference_view(
                127,
                "exitCodes.default.127.title",
                "exitCodes.default.127.summary",
                "error",
                strings,
            ),
        ),
        (
            130,
            exit_code_reference_view(
                130,
                "exitCodes.default.130.title",
                "exitCodes.default.130.summary",
                "warning",
                strings,
            ),
        ),
    ]);
    for entry in overrides {
        references.insert(
            entry.code,
            ExitCodeReferenceView {
                title: localize(Some(entry.title.as_str()), strings)
                    .unwrap_or_else(|| entry.title.clone()),
                summary: localize(Some(entry.summary.as_str()), strings)
                    .unwrap_or_else(|| entry.summary.clone()),
                severity: entry
                    .severity
                    .as_deref()
                    .filter(|severity| *severity == "warning")
                    .unwrap_or("error")
                    .to_string(),
            },
        );
    }
    references
}

pub fn explain(status: i32, references: &BTreeMap<i32, ExitCodeReferenceView>) -> ExitExplanation {
    if let Some(reference) = references.get(&status) {
        return ExitExplanation {
            title: reference.title.clone(),
            summary: reference.summary.clone(),
            severity: reference.severity.clone(),
        };
    }
    ExitExplanation {
        title: format!("Exit code {status}"),
        summary: "The command failed. Check the output above for details.".to_string(),
        severity: "error".to_string(),
    }
}

fn exit_code_reference_view(
    code: i32,
    title_key: &str,
    summary_key: &str,
    severity: &str,
    strings: &BTreeMap<String, String>,
) -> ExitCodeReferenceView {
    ExitCodeReferenceView {
        title: localize(Some(title_key), strings).unwrap_or_else(|| format!("Exit code {code}")),
        summary: localize(Some(summary_key), strings).unwrap_or_else(|| {
            "The command failed. Check the output above for details.".to_string()
        }),
        severity: severity.to_string(),
    }
}

fn localize(value: Option<&str>, strings: &BTreeMap<String, String>) -> Option<String> {
    value.map(|value| {
        strings
            .get(value)
            .cloned()
            .unwrap_or_else(|| value.to_string())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn explain_uses_manifest_reference() {
        let references = BTreeMap::from([(
            42,
            ExitCodeReferenceView {
                title: "Disk estimate failed".to_string(),
                summary: "Check available storage before retrying.".to_string(),
                severity: "warning".to_string(),
            },
        )]);

        let explanation = explain(42, &references);

        assert_eq!(explanation.title, "Disk estimate failed");
        assert_eq!(
            explanation.summary,
            "Check available storage before retrying."
        );
        assert_eq!(explanation.severity, "warning");
    }
}
