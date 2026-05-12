use crate::bundle::{ActionConfirmationView, ActionView, ControlView};
use crate::data_source_cache;
use crate::execution::{disabled_reason, interpolate_fields, is_action_visible};
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;

pub fn data_source_row_actions(
    controls: &[ControlView],
    field_values: &BTreeMap<String, String>,
    data_source_cache: &mut BTreeMap<String, String>,
    bundle_root: &Path,
) -> Vec<ActionView> {
    let mut actions = Vec::new();
    for control in controls {
        if control.row_actions.is_empty() {
            continue;
        }
        let Some(data_source) = &control.data_source else {
            continue;
        };
        let Ok(payload) =
            data_source_cache::payload(data_source, field_values, data_source_cache, bundle_root)
        else {
            continue;
        };
        let Some(items) = payload.get("items").and_then(Value::as_array) else {
            continue;
        };
        for (row_index, item) in items.iter().enumerate() {
            let Some(row_values) = item.get("values").and_then(Value::as_object) else {
                continue;
            };
            let mut context = field_values.clone();
            for (key, value) in row_values {
                let value = json_scalar(value);
                context.insert(key.clone(), value.clone());
                context.insert(format!("row.{key}"), value);
            }
            let row_label = row_label(item, row_values);
            let row_identifier = row_identifier(item, row_values, row_index);
            for action in &control.row_actions {
                if !is_action_visible(action, &context)
                    || disabled_reason(action, &context).is_some()
                {
                    continue;
                }
                actions.push(materialize_row_action(
                    &control.id,
                    action,
                    &context,
                    &row_label,
                    &row_identifier,
                ));
            }
        }
    }
    actions
}

fn materialize_row_action(
    control_id: &str,
    action: &ActionView,
    context: &BTreeMap<String, String>,
    row_label: &str,
    row_identifier: &str,
) -> ActionView {
    let title = if row_label.trim().is_empty() {
        action.title.clone()
    } else {
        format!("{row_label}: {}", action.title)
    };
    ActionView {
        id: format!("{control_id}:{}:{row_identifier}", action.id),
        title,
        role: action.role.clone(),
        executable: interpolate_fields(&action.executable, context),
        arguments: action
            .arguments
            .iter()
            .map(|argument| interpolate_fields(argument, context))
            .collect(),
        optional_arguments: action
            .optional_arguments
            .iter()
            .map(|group| {
                group
                    .iter()
                    .map(|argument| interpolate_fields(argument, context))
                    .collect()
            })
            .collect(),
        environment: action
            .environment
            .iter()
            .map(|(key, value)| (key.clone(), interpolate_fields(value, context)))
            .collect(),
        working_directory: action
            .working_directory
            .as_ref()
            .map(|value| interpolate_fields(value, context)),
        visible_when: Vec::new(),
        disabled_when: Vec::new(),
        disabled_tooltip: interpolate_fields(&action.disabled_tooltip, context),
        confirmation: action
            .confirmation
            .as_ref()
            .map(|confirmation| materialize_confirmation(confirmation, context)),
    }
}

fn materialize_confirmation(
    confirmation: &ActionConfirmationView,
    context: &BTreeMap<String, String>,
) -> ActionConfirmationView {
    ActionConfirmationView {
        title: interpolate_fields(&confirmation.title, context),
        message: interpolate_fields(&confirmation.message, context),
        confirm_button_title: interpolate_fields(&confirmation.confirm_button_title, context),
        cancel_button_title: interpolate_fields(&confirmation.cancel_button_title, context),
        required_text: interpolate_fields(&confirmation.required_text, context),
        prompt: interpolate_fields(&confirmation.prompt, context),
    }
}

fn row_label(item: &Value, row_values: &serde_json::Map<String, Value>) -> String {
    item.get("title")
        .and_then(Value::as_str)
        .or_else(|| row_values.get("name").and_then(Value::as_str))
        .or_else(|| row_values.get("final").and_then(Value::as_str))
        .or_else(|| row_values.get("code").and_then(Value::as_str))
        .or_else(|| row_values.get("id").and_then(Value::as_str))
        .unwrap_or("row")
        .to_string()
}

fn row_identifier(
    item: &Value,
    row_values: &serde_json::Map<String, Value>,
    row_index: usize,
) -> String {
    item.get("id")
        .and_then(Value::as_str)
        .or_else(|| row_values.get("id").and_then(Value::as_str))
        .map(safe_identifier)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| row_index.to_string())
}

fn safe_identifier(value: &str) -> String {
    value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.') {
                character
            } else {
                '-'
            }
        })
        .collect::<String>()
        .trim_matches('-')
        .to_string()
}

fn json_scalar(value: &Value) -> String {
    value
        .as_str()
        .map(ToString::to_string)
        .unwrap_or_else(|| value.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn materialized_row_action_resolves_row_context() {
        let mut context = BTreeMap::new();
        context.insert("ref_path".to_string(), "/refs".to_string());
        context.insert("code".to_string(), "hg38".to_string());
        context.insert("row.code".to_string(), "hg38".to_string());
        context.insert("final".to_string(), "GRCh38".to_string());
        context.insert("row.final".to_string(), "GRCh38".to_string());
        let action = ActionView {
            id: "ref-delete".to_string(),
            title: "Delete".to_string(),
            role: "destructive".to_string(),
            executable: "/bin/delete-reference".to_string(),
            arguments: vec!["{{ref_path}}".to_string(), "{{row.final}}".to_string()],
            optional_arguments: vec![vec!["--code".to_string(), "{{row.code}}".to_string()]],
            environment: BTreeMap::from([(
                "REFERENCE_CODE".to_string(),
                "{{row.code}}".to_string(),
            )]),
            working_directory: Some("{{ref_path}}/{{row.code}}".to_string()),
            visible_when: Vec::new(),
            disabled_when: Vec::new(),
            disabled_tooltip: String::new(),
            confirmation: Some(ActionConfirmationView {
                title: "Delete {{row.final}}?".to_string(),
                message: "{{row.final}} will be removed.".to_string(),
                confirm_button_title: "Delete".to_string(),
                cancel_button_title: "Cancel".to_string(),
                required_text: "{{row.final}}".to_string(),
                prompt: "Type {{row.final}}".to_string(),
            }),
        };

        let materialized =
            materialize_row_action("reference_genomes", &action, &context, "GRCh38", "hg38");

        assert_eq!(materialized.id, "reference_genomes:ref-delete:hg38");
        assert_eq!(materialized.title, "GRCh38: Delete");
        assert_eq!(
            materialized.arguments,
            vec!["/refs".to_string(), "GRCh38".to_string()]
        );
        assert_eq!(
            materialized.optional_arguments,
            vec![vec!["--code".to_string(), "hg38".to_string()]]
        );
        assert_eq!(
            materialized.environment.get("REFERENCE_CODE"),
            Some(&"hg38".to_string())
        );
        assert_eq!(
            materialized.working_directory,
            Some("/refs/hg38".to_string())
        );
        let confirmation = materialized.confirmation.expect("confirmation");
        assert_eq!(confirmation.required_text, "GRCh38");
        assert_eq!(confirmation.prompt, "Type GRCh38");
        assert!(materialized.visible_when.is_empty());
        assert!(materialized.disabled_when.is_empty());
    }

    #[test]
    fn row_identifier_falls_back_to_row_index_for_duplicate_labels() {
        let item = serde_json::json!({
            "title": "Duplicate",
            "values": {
                "name": "Duplicate"
            }
        });
        let values = item
            .get("values")
            .and_then(Value::as_object)
            .expect("values");

        assert_eq!(row_identifier(&item, values, 0), "0");
        assert_eq!(row_identifier(&item, values, 1), "1");
    }
}
