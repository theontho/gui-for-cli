use crate::exit_codes::{ExitCodeReference, ExitCodeReferenceView, effective_exit_code_reference};
use anyhow::{Context, Result, anyhow};
use serde::Deserialize;
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

#[derive(Debug, Deserialize)]
struct Manifest {
    id: String,
    #[serde(rename = "displayName")]
    display_name: Option<String>,
    summary: Option<String>,
    #[serde(rename = "exitCodeReference", default)]
    exit_code_reference: Vec<ExitCodeReference>,
    #[serde(rename = "terminalTextDirection")]
    terminal_text_direction: Option<String>,
    #[serde(default)]
    pages: Vec<Value>,
    #[serde(default)]
    setup: Setup,
}

#[derive(Debug, Default, Deserialize)]
struct Setup {
    #[serde(default)]
    steps: Vec<SetupStep>,
}

#[derive(Debug, Deserialize)]
struct SetupStep {
    id: String,
    label: Option<String>,
    kind: Option<String>,
    value: Option<String>,
    #[serde(default)]
    arguments: Vec<String>,
    #[serde(default)]
    environment: BTreeMap<String, String>,
    #[serde(rename = "workingDirectory")]
    working_directory: Option<String>,
    #[serde(default)]
    optional: bool,
}

#[derive(Debug, Deserialize)]
struct Page {
    id: String,
    title: Option<String>,
    summary: Option<String>,
    #[serde(default)]
    sections: Vec<Section>,
}

#[derive(Debug, Deserialize)]
struct Section {
    id: String,
    title: Option<String>,
    subtitle: Option<String>,
    #[serde(default)]
    controls: Vec<Control>,
    #[serde(default)]
    actions: Vec<Action>,
    #[serde(rename = "dataSource")]
    data_source: Option<DataSource>,
}

#[derive(Debug, Deserialize)]
struct Control {
    id: String,
    label: Option<String>,
    kind: Option<String>,
    value: Option<Value>,
    placeholder: Option<String>,
    tooltip: Option<String>,
    #[serde(default)]
    options: Vec<OptionItem>,
    #[serde(rename = "rowActions", default)]
    row_actions: Vec<Action>,
    #[serde(rename = "dataSource")]
    data_source: Option<DataSource>,
    #[serde(default)]
    columns: Vec<Column>,
    #[serde(default)]
    settings: Vec<ConfigSetting>,
    #[serde(rename = "configFile")]
    config_file: Option<ConfigFile>,
}

#[derive(Debug, Deserialize)]
struct ConfigSetting {
    id: String,
    key: Option<String>,
    label: Option<String>,
    kind: Option<String>,
    value: Option<Value>,
    placeholder: Option<String>,
    tooltip: Option<String>,
    #[serde(rename = "dataSource")]
    data_source: Option<DataSource>,
    #[serde(default)]
    options: Vec<OptionItem>,
}

#[derive(Debug, Deserialize)]
struct ConfigFile {
    path: Option<String>,
    format: Option<String>,
}

#[derive(Debug, Deserialize)]
struct DataSource {
    path: String,
    #[serde(default)]
    arguments: Vec<String>,
    #[serde(default)]
    environment: BTreeMap<String, String>,
    #[serde(rename = "workingDirectory")]
    working_directory: Option<String>,
}

#[derive(Debug, Deserialize)]
struct OptionItem {
    id: String,
    title: Option<String>,
    group: Option<String>,
    #[serde(default)]
    selected: bool,
}

#[derive(Debug, Deserialize)]
struct Column {
    id: String,
    title: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Action {
    id: String,
    title: Option<String>,
    tooltip: Option<String>,
    role: Option<String>,
    #[serde(rename = "visibleWhen", default)]
    visible_when: Vec<ActionCondition>,
    #[serde(rename = "disabledWhen", default)]
    disabled_when: Vec<ActionCondition>,
    #[serde(rename = "disabledTooltip")]
    disabled_tooltip: Option<String>,
    confirm: Option<ActionConfirmation>,
    command: Option<Command>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ActionCondition {
    pub placeholder: String,
    pub equals: Option<String>,
    #[serde(rename = "notEquals")]
    pub not_equals: Option<String>,
    #[serde(rename = "in", default)]
    pub in_values: Vec<String>,
    #[serde(rename = "notIn", default)]
    pub not_in_values: Vec<String>,
    pub exists: Option<bool>,
    #[serde(rename = "lessThan")]
    pub less_than: Option<String>,
    #[serde(rename = "lessThanOrEqual")]
    pub less_than_or_equal: Option<String>,
    #[serde(rename = "greaterThan")]
    pub greater_than: Option<String>,
    #[serde(rename = "greaterThanOrEqual")]
    pub greater_than_or_equal: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct ActionConfirmation {
    title: String,
    message: Option<String>,
    #[serde(rename = "confirmButtonTitle")]
    confirm_button_title: Option<String>,
    #[serde(rename = "cancelButtonTitle")]
    cancel_button_title: Option<String>,
    #[serde(rename = "requiredText")]
    required_text: Option<String>,
    prompt: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Command {
    executable: Option<String>,
    #[serde(default)]
    arguments: Vec<String>,
    #[serde(rename = "optionalArguments", default)]
    optional_arguments: Vec<Vec<String>>,
}

#[derive(Debug)]
pub struct BundleView {
    pub title: String,
    pub summary: String,
    pub exit_code_reference: BTreeMap<i32, ExitCodeReferenceView>,
    #[allow(dead_code)]
    pub strings: BTreeMap<String, String>,
    #[allow(dead_code)]
    pub terminal_text_direction: String,
    pub setup_lines: Vec<String>,
    pub setup_steps: Vec<SetupStepView>,
    pub pages: Vec<PageView>,
    pub control_count: usize,
    pub action_count: usize,
    pub data_source_count: usize,
}

#[derive(Debug, Clone)]
pub struct PageView {
    pub id: String,
    pub title: String,
    pub summary: String,
    pub body: String,
    pub controls: Vec<ControlView>,
    pub actions: Vec<ActionView>,
}

#[derive(Debug, Clone)]
pub struct ControlView {
    pub id: String,
    pub label: String,
    pub kind: String,
    pub value: String,
    pub placeholder: String,
    pub helper: String,
    pub options: String,
    pub option_items: Vec<OptionView>,
    pub data_source: Option<DataSourceView>,
    pub columns: Vec<ColumnView>,
    pub row_actions: Vec<ActionView>,
    pub config_file_path: String,
    pub config_key: String,
}

#[derive(Debug, Clone)]
pub struct ActionView {
    pub id: String,
    pub title: String,
    pub role: String,
    pub executable: String,
    pub arguments: Vec<String>,
    pub optional_arguments: Vec<Vec<String>>,
    pub environment: BTreeMap<String, String>,
    pub working_directory: Option<String>,
    pub visible_when: Vec<ActionCondition>,
    pub disabled_when: Vec<ActionCondition>,
    pub disabled_tooltip: String,
    pub confirmation: Option<ActionConfirmationView>,
}

#[derive(Debug, Clone)]
pub struct ActionConfirmationView {
    pub title: String,
    pub message: String,
    pub confirm_button_title: String,
    pub cancel_button_title: String,
    pub required_text: String,
    pub prompt: String,
}

#[derive(Debug, Clone)]
pub struct SetupStepView {
    pub label: String,
    pub kind: String,
    pub value: String,
    pub arguments: Vec<String>,
    pub environment: BTreeMap<String, String>,
    pub working_directory: Option<String>,
    pub optional: bool,
}

#[derive(Debug, Clone)]
pub struct DataSourceView {
    pub path: String,
    pub arguments: Vec<String>,
    pub environment: BTreeMap<String, String>,
    pub working_directory: Option<String>,
}

#[derive(Debug, Clone)]
pub struct OptionView {
    pub id: String,
    pub title: String,
    pub group: String,
    pub selected: bool,
}

#[derive(Debug, Clone)]
pub struct ColumnView {
    pub id: String,
    pub title: String,
}

pub fn load_bundle(bundle_root: &Path, repo_root: &Path, locale: &str) -> Result<BundleView> {
    let manifest_path = bundle_root.join("manifest.json");
    let manifest: Manifest = read_json(&manifest_path)?;
    let strings = load_strings(bundle_root, repo_root, locale)?;
    let mut pages = Vec::new();

    for page_value in &manifest.pages {
        let page = match page_value {
            Value::String(page_file) => {
                if page_file.contains('/') || page_file.contains('\\') || page_file.contains("..") {
                    return Err(anyhow!("invalid page file name: {page_file}"));
                }
                read_json(&bundle_root.join("pages").join(page_file))?
            }
            value => serde_json::from_value(value.clone()).context("decode inline page")?,
        };
        pages.push(render_page(page, &strings, bundle_root));
    }

    let control_count = pages.iter().map(|page| page.controls.len()).sum();
    let action_count = pages.iter().map(|page| page.actions.len()).sum();
    let data_source_count = pages
        .iter()
        .flat_map(|page| page.controls.iter())
        .filter(|control| control.data_source.is_some())
        .count();

    Ok(BundleView {
        title: localize_opt(manifest.display_name.as_deref(), &strings)
            .unwrap_or_else(|| manifest.id.clone()),
        summary: localize_opt(manifest.summary.as_deref(), &strings).unwrap_or_default(),
        exit_code_reference: effective_exit_code_reference(&manifest.exit_code_reference, &strings),
        strings: strings.clone(),
        terminal_text_direction: manifest
            .terminal_text_direction
            .map(|value| value.trim().to_ascii_lowercase())
            .filter(|value| value == "rtl")
            .unwrap_or_else(|| "ltr".to_string()),
        setup_lines: render_setup(&manifest.setup, &strings),
        setup_steps: setup_step_views(&manifest.setup, &strings, bundle_root),
        pages,
        control_count,
        action_count,
        data_source_count,
    })
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> Result<T> {
    let text = fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
    serde_json::from_str(&text).with_context(|| format!("parse {}", path.display()))
}

fn load_strings(
    bundle_root: &Path,
    repo_root: &Path,
    locale: &str,
) -> Result<BTreeMap<String, String>> {
    let mut strings = BTreeMap::new();
    merge_strings(
        &mut strings,
        &repo_root
            .join("Sources")
            .join("GUIForCLICore")
            .join("Resources")
            .join("BuiltinStrings")
            .join("strings.en.toml"),
    )?;
    if locale != "en" {
        merge_strings(
            &mut strings,
            &repo_root
                .join("Sources")
                .join("GUIForCLICore")
                .join("Resources")
                .join("BuiltinStrings")
                .join(format!("strings.{locale}.toml")),
        )?;
    }
    let bundle_strings = if locale == "en" {
        bundle_root.join("strings").join("strings.en.toml")
    } else {
        bundle_root
            .join("strings")
            .join(format!("strings.{locale}.toml"))
    };
    merge_strings(&mut strings, &bundle_strings)?;
    Ok(strings)
}

fn merge_strings(target: &mut BTreeMap<String, String>, path: &Path) -> Result<()> {
    if !path.exists() {
        return Ok(());
    }

    let text = fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
    let value = toml::from_str::<toml::Value>(&text)
        .with_context(|| format!("parse {}", path.display()))?;
    if let Some(table) = value.as_table() {
        for (key, value) in table {
            if let Some(value) = value.as_str() {
                target.insert(key.clone(), value.to_string());
            }
        }
    }
    Ok(())
}

fn render_setup(setup: &Setup, strings: &BTreeMap<String, String>) -> Vec<String> {
    setup
        .steps
        .iter()
        .map(|step| {
            let label =
                localize_opt(step.label.as_deref(), strings).unwrap_or_else(|| step.id.clone());
            let kind = step.kind.as_deref().unwrap_or("step");
            let value = step.value.as_deref().unwrap_or("");
            let optional = if step.optional { " optional" } else { "" };
            format!("• {label} ({kind}{optional}) {value}")
        })
        .collect()
}

fn setup_step_views(
    setup: &Setup,
    strings: &BTreeMap<String, String>,
    bundle_root: &Path,
) -> Vec<SetupStepView> {
    setup
        .steps
        .iter()
        .map(|step| SetupStepView {
            label: localize_opt(step.label.as_deref(), strings).unwrap_or_else(|| step.id.clone()),
            kind: step.kind.clone().unwrap_or_else(|| "step".to_string()),
            value: step
                .value
                .as_deref()
                .map(|value| interpolate_builtin(value, bundle_root))
                .unwrap_or_default(),
            arguments: step
                .arguments
                .iter()
                .map(|argument| interpolate_builtin(argument, bundle_root))
                .collect(),
            environment: step
                .environment
                .iter()
                .map(|(key, value)| (key.clone(), interpolate_builtin(value, bundle_root)))
                .collect(),
            working_directory: step
                .working_directory
                .as_deref()
                .map(|value| interpolate_builtin(value, bundle_root)),
            optional: step.optional,
        })
        .collect()
}

fn render_page(page: Page, strings: &BTreeMap<String, String>, bundle_root: &Path) -> PageView {
    let mut body = Vec::new();
    let mut controls = Vec::new();
    let mut actions = Vec::new();
    for section in page.sections {
        let section_id = section.id.clone();
        let section_title =
            localize_opt(section.title.as_deref(), strings).unwrap_or_else(|| section.id.clone());
        body.push(format!("## {section_title}"));
        if let Some(subtitle) = localize_opt(section.subtitle.as_deref(), strings) {
            body.push(subtitle);
        }
        if let Some(data_source) = section.data_source {
            body.push(format!(
                "  data source: {} {}",
                data_source.path,
                data_source.arguments.join(" ")
            ));
            controls.push(ControlView {
                id: format!("section-data-source-{section_id}"),
                label: format!("{section_title} status"),
                kind: "infoGrid".to_string(),
                value: String::new(),
                placeholder: String::new(),
                helper: String::new(),
                options: String::new(),
                option_items: Vec::new(),
                data_source: Some(data_source_view(&data_source, bundle_root)),
                columns: Vec::new(),
                row_actions: Vec::new(),
                config_file_path: String::new(),
                config_key: String::new(),
            });
        }
        for control in section.controls {
            let (text, control_views, control_actions) =
                render_control(control, strings, bundle_root);
            body.push(text);
            controls.extend(control_views);
            actions.extend(control_actions);
        }
        for action in section.actions {
            body.push(render_action(&action, strings, ""));
            if let Some(view) = action_view(action, strings, bundle_root) {
                actions.push(view);
            }
        }
        body.push(String::new());
    }

    PageView {
        id: page.id.clone(),
        title: localize_opt(page.title.as_deref(), strings).unwrap_or(page.id),
        summary: localize_opt(page.summary.as_deref(), strings).unwrap_or_default(),
        body: body.join("\n"),
        controls,
        actions,
    }
}

fn render_control(
    control: Control,
    strings: &BTreeMap<String, String>,
    bundle_root: &Path,
) -> (String, Vec<ControlView>, Vec<ActionView>) {
    let label =
        localize_opt(control.label.as_deref(), strings).unwrap_or_else(|| control.id.clone());
    let kind = control.kind.unwrap_or_else(|| "text".to_string());
    let mut lines = vec![format!("• {label} ({kind})")];
    let mut controls = Vec::new();
    let actions = Vec::new();
    let value = control
        .value
        .as_ref()
        .map(value_to_string)
        .unwrap_or_default();
    let placeholder = localize_opt(control.placeholder.as_deref(), strings).unwrap_or_default();
    let helper = localize_opt(control.tooltip.as_deref(), strings).unwrap_or_default();
    let options = option_titles(&control.options, strings);
    let option_items = option_views(&control.options, strings);
    let data_source = control
        .data_source
        .as_ref()
        .map(|data_source| data_source_view(data_source, bundle_root));
    let columns = column_views(&control.columns, strings);
    let config_file_path = control
        .config_file
        .as_ref()
        .and_then(|config_file| config_file.path.as_deref())
        .map(|path| interpolate_builtin(path, bundle_root))
        .unwrap_or_default();
    let row_actions = control
        .row_actions
        .iter()
        .filter_map(|action| action_view_ref(action, strings, bundle_root))
        .collect::<Vec<_>>();
    if let Some(config_file) = &control.config_file {
        let path = config_file.path.as_deref().unwrap_or("");
        let format = config_file.format.as_deref().unwrap_or("config");
        lines.push(format!("  config file ({format}): {path}"));
    }
    if is_editable_control(&kind) {
        let value = if kind == "checkboxGroup" && value.is_empty() {
            selected_option_ids(&option_items)
        } else {
            value.clone()
        };
        controls.push(ControlView {
            id: control.id.clone(),
            label: label.clone(),
            kind: kind.clone(),
            value,
            placeholder: placeholder.clone(),
            helper: helper.clone(),
            options: options.clone(),
            option_items: option_items.clone(),
            data_source: data_source.clone(),
            columns: columns.clone(),
            row_actions: row_actions.clone(),
            config_file_path: String::new(),
            config_key: String::new(),
        });
    }

    if !value.is_empty() {
        lines.push(format!("  default: {value}"));
    }
    if let Some(data_source) = &control.data_source {
        lines.push(format!(
            "  data source: {} {}",
            data_source.path,
            data_source.arguments.join(" ")
        ));
    }
    if !options.is_empty() {
        lines.push(format!("  options: {options}"));
    }
    if !helper.is_empty() {
        lines.push(format!("  {helper}"));
    }
    for setting in control.settings {
        let label =
            localize_opt(setting.label.as_deref(), strings).unwrap_or_else(|| setting.id.clone());
        let config_key = setting.key.clone().unwrap_or_else(|| setting.id.clone());
        let kind = setting.kind.unwrap_or_else(|| "text".to_string());
        let value = setting
            .value
            .map(|value| value_to_string(&value))
            .unwrap_or_default();
        let placeholder = localize_opt(setting.placeholder.as_deref(), strings).unwrap_or_default();
        let helper = localize_opt(setting.tooltip.as_deref(), strings).unwrap_or_default();
        let options = option_titles(&setting.options, strings);
        let option_items = option_views(&setting.options, strings);
        let data_source = setting
            .data_source
            .as_ref()
            .map(|data_source| data_source_view(data_source, bundle_root));
        if is_editable_control(&kind) {
            controls.push(ControlView {
                id: setting.id.clone(),
                label: label.clone(),
                kind: kind.clone(),
                value: value.clone(),
                placeholder,
                helper: helper.clone(),
                options,
                option_items,
                data_source,
                columns: Vec::new(),
                row_actions: Vec::new(),
                config_file_path: config_file_path.clone(),
                config_key: config_key.clone(),
            });
        }
        lines.push(format!("  setting: {label} ({kind}) {value}"));
        if !helper.is_empty() {
            lines.push(format!("    {helper}"));
        }
        if let Some(data_source) = &setting.data_source {
            lines.push(format!(
                "    data source: {} {}",
                data_source.path,
                data_source.arguments.join(" ")
            ));
        }
    }
    for action in control.row_actions {
        lines.push(render_action(&action, strings, "  row action: "));
    }

    (lines.join("\n"), controls, actions)
}

fn render_action(action: &Action, strings: &BTreeMap<String, String>, prefix: &str) -> String {
    let title = localize_opt(action.title.as_deref(), strings).unwrap_or_else(|| action.id.clone());
    let role = action.role.as_deref().unwrap_or("primary");
    let mut lines = vec![format!("{prefix}▶ {title} ({role})")];
    if let Some(tooltip) = localize_opt(action.tooltip.as_deref(), strings) {
        lines.push(format!("  {tooltip}"));
    }
    if let Some(command) = &action.command {
        let preview = render_command(command, Path::new(""));
        lines.push(format!("  command: {preview}"));
    }
    lines.join("\n")
}

fn action_view(
    action: Action,
    strings: &BTreeMap<String, String>,
    bundle_root: &Path,
) -> Option<ActionView> {
    action_view_ref(&action, strings, bundle_root)
}

fn action_view_ref(
    action: &Action,
    strings: &BTreeMap<String, String>,
    bundle_root: &Path,
) -> Option<ActionView> {
    let command = action.command.as_ref()?;
    let executable = interpolate_builtin(
        command.executable.as_deref().unwrap_or_default(),
        bundle_root,
    );
    let arguments = command_arguments(command, bundle_root);
    let optional_arguments = optional_command_arguments(command, bundle_root);
    Some(ActionView {
        id: action.id.clone(),
        title: localize_opt(action.title.as_deref(), strings).unwrap_or_else(|| action.id.clone()),
        role: action.role.clone().unwrap_or_else(|| "primary".to_string()),
        executable,
        arguments,
        optional_arguments,
        environment: BTreeMap::new(),
        working_directory: None,
        visible_when: action.visible_when.clone(),
        disabled_when: action.disabled_when.clone(),
        disabled_tooltip: localize_opt(action.disabled_tooltip.as_deref(), strings)
            .unwrap_or_else(|| "This action is not available.".to_string()),
        confirmation: action
            .confirm
            .as_ref()
            .map(|confirm| action_confirmation_view(confirm, strings)),
    })
}

fn action_confirmation_view(
    confirm: &ActionConfirmation,
    strings: &BTreeMap<String, String>,
) -> ActionConfirmationView {
    ActionConfirmationView {
        title: localize_opt(Some(confirm.title.as_str()), strings)
            .unwrap_or_else(|| confirm.title.clone()),
        message: localize_opt(confirm.message.as_deref(), strings).unwrap_or_default(),
        confirm_button_title: localize_opt(confirm.confirm_button_title.as_deref(), strings)
            .unwrap_or_else(|| "Continue".to_string()),
        cancel_button_title: localize_opt(confirm.cancel_button_title.as_deref(), strings)
            .unwrap_or_else(|| "Cancel".to_string()),
        required_text: confirm.required_text.clone().unwrap_or_default(),
        prompt: localize_opt(confirm.prompt.as_deref(), strings).unwrap_or_default(),
    }
}

fn render_command(command: &Command, bundle_root: &Path) -> String {
    std::iter::once(interpolate_builtin(
        command.executable.as_deref().unwrap_or_default(),
        bundle_root,
    ))
    .chain(command_arguments(command, bundle_root))
    .collect::<Vec<_>>()
    .join(" ")
}

fn command_arguments(command: &Command, bundle_root: &Path) -> Vec<String> {
    command
        .arguments
        .iter()
        .map(|argument| interpolate_builtin(argument, bundle_root))
        .collect::<Vec<_>>()
}

fn optional_command_arguments(command: &Command, bundle_root: &Path) -> Vec<Vec<String>> {
    command
        .optional_arguments
        .iter()
        .map(|group| {
            group
                .iter()
                .map(|argument| interpolate_builtin(argument, bundle_root))
                .collect::<Vec<_>>()
        })
        .collect()
}

fn interpolate_builtin(value: &str, bundle_root: &Path) -> String {
    let home = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_default();
    value
        .replace("{{bundleRoot}}", &bundle_root.display().to_string())
        .replace("{{bundleWorkspace}}", &bundle_root.display().to_string())
        .replace("{{home}}", &home)
}

fn option_titles(options: &[OptionItem], strings: &BTreeMap<String, String>) -> String {
    options
        .iter()
        .map(|option| {
            localize_opt(option.title.as_deref(), strings).unwrap_or_else(|| option.id.clone())
        })
        .collect::<Vec<_>>()
        .join(", ")
}

fn option_views(options: &[OptionItem], strings: &BTreeMap<String, String>) -> Vec<OptionView> {
    options
        .iter()
        .map(|option| OptionView {
            id: option.id.clone(),
            title: localize_opt(option.title.as_deref(), strings)
                .unwrap_or_else(|| option.id.clone()),
            group: option.group.clone().unwrap_or_default(),
            selected: option.selected,
        })
        .collect()
}

fn selected_option_ids(options: &[OptionView]) -> String {
    options
        .iter()
        .filter(|option| option.selected)
        .map(|option| option.id.clone())
        .collect::<Vec<_>>()
        .join(",")
}

fn column_views(columns: &[Column], strings: &BTreeMap<String, String>) -> Vec<ColumnView> {
    columns
        .iter()
        .map(|column| ColumnView {
            id: column.id.clone(),
            title: localize_opt(column.title.as_deref(), strings)
                .unwrap_or_else(|| column.id.clone()),
        })
        .collect()
}

fn data_source_view(data_source: &DataSource, bundle_root: &Path) -> DataSourceView {
    DataSourceView {
        path: interpolate_builtin(&data_source.path, bundle_root),
        arguments: data_source
            .arguments
            .iter()
            .map(|argument| interpolate_builtin(argument, bundle_root))
            .collect(),
        environment: data_source
            .environment
            .iter()
            .map(|(key, value)| (key.clone(), interpolate_builtin(value, bundle_root)))
            .collect(),
        working_directory: data_source
            .working_directory
            .as_deref()
            .map(|value| interpolate_builtin(value, bundle_root)),
    }
}

fn is_editable_control(kind: &str) -> bool {
    matches!(
        kind,
        "text" | "path" | "dropdown" | "toggle" | "checkboxGroup" | "infoGrid" | "libraryList"
    )
}

fn localize_opt(value: Option<&str>, strings: &BTreeMap<String, String>) -> Option<String> {
    value.map(|value| {
        strings
            .get(value)
            .cloned()
            .unwrap_or_else(|| value.to_string())
    })
}

fn value_to_string(value: &Value) -> String {
    match value {
        Value::String(value) => value.clone(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        _ => value.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};

    #[test]
    fn loads_wgs_extract_bundle() {
        let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .and_then(Path::parent)
            .expect("repo root")
            .to_path_buf();
        let bundle = load_bundle(
            &repo_root.join("Examples").join("WGSExtract"),
            &repo_root,
            "en",
        )
        .expect("load bundle");

        assert_eq!(bundle.title, "WGS Extract");
        assert!(bundle.pages.iter().any(|page| page.title == "FASTQ"));
        assert!(
            bundle
                .pages
                .iter()
                .any(|page| page.body.contains("command:"))
        );
        let command_not_found = bundle
            .exit_code_reference
            .get(&127)
            .expect("default exit code 127 reference");
        assert_eq!(command_not_found.title, "Command not found");
        assert!(command_not_found.summary.contains("runtime workspace"));
        assert_eq!(command_not_found.severity, "error");
    }
}
