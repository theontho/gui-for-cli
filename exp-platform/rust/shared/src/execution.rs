use crate::bundle::{ActionView, DataSourceView, SetupStepView};
use crate::exit_codes::{ExitCodeReferenceView, explain};
use anyhow::{Context, Result, anyhow};
use serde_json::Value;
use std::collections::BTreeMap;
use std::io::Read;
#[cfg(unix)]
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

const DATA_SOURCE_TIMEOUT: Duration = Duration::from_secs(15);
const STDOUT_LIMIT: usize = 1_048_576;
const STDERR_LIMIT: usize = 65_536;

pub fn prepare_action_command(
    action: &ActionView,
    field_values: &BTreeMap<String, String>,
    bundle_root: &Path,
) -> Result<PreparedCommand> {
    if let Some(reason) = action_unavailable_reason(action, field_values) {
        return Err(anyhow!(reason));
    }

    let mut env = action.environment.clone();
    add_context_environment(&mut env, field_values, bundle_root);
    Ok(PreparedCommand {
        title: action.title.clone(),
        executable: interpolate_fields(&action.executable, field_values),
        arguments: action_arguments(action, field_values),
        cwd: action
            .working_directory
            .as_deref()
            .map(|path| resolve_bundle_path(path, bundle_root))
            .unwrap_or_else(|| bundle_root.to_path_buf()),
        env,
        exit_code_reference: BTreeMap::new(),
    })
}

pub fn action_unavailable_reason(
    action: &ActionView,
    field_values: &BTreeMap<String, String>,
) -> Option<String> {
    if let Some(reason) = disabled_reason(action, field_values) {
        return Some(reason);
    }
    let missing =
        missing_required_placeholders(&action.executable, &action.arguments, field_values);
    if missing.is_empty() {
        None
    } else {
        Some(format!(
            "Fill required values: {}",
            missing
                .iter()
                .map(|placeholder| readable_placeholder(placeholder))
                .collect::<Vec<_>>()
                .join(", ")
        ))
    }
}

pub fn action_preview(action: &ActionView, field_values: &BTreeMap<String, String>) -> String {
    display_command(
        &interpolate_fields(&action.executable, field_values),
        &action_arguments(action, field_values),
    )
}

pub fn is_action_visible(action: &ActionView, field_values: &BTreeMap<String, String>) -> bool {
    action
        .visible_when
        .iter()
        .all(|condition| condition_matches(condition, field_values))
}

pub fn disabled_reason(
    action: &ActionView,
    field_values: &BTreeMap<String, String>,
) -> Option<String> {
    action
        .disabled_when
        .iter()
        .any(|condition| condition_matches(condition, field_values))
        .then(|| {
            if action.disabled_tooltip.trim().is_empty() {
                "This action is not available.".to_string()
            } else {
                interpolate_fields(&action.disabled_tooltip, field_values)
            }
        })
}

pub fn confirmation_prompt(
    action: &ActionView,
    field_values: &BTreeMap<String, String>,
) -> Option<String> {
    let confirmation = action.confirmation.as_ref()?;
    let mut lines = vec![format!(
        "{}: {}",
        interpolate_fields(&confirmation.title, field_values),
        interpolate_fields(&confirmation.confirm_button_title, field_values)
    )];
    if !confirmation.message.trim().is_empty() {
        lines.push(interpolate_fields(&confirmation.message, field_values));
    }
    if !confirmation.prompt.trim().is_empty() {
        lines.push(interpolate_fields(&confirmation.prompt, field_values));
    }
    if !confirmation.required_text.trim().is_empty() {
        lines.push(format!(
            "Required text: {}",
            interpolate_fields(&confirmation.required_text, field_values)
        ));
    }
    if !confirmation.cancel_button_title.trim().is_empty() {
        lines.push(format!(
            "Cancel action: {}",
            interpolate_fields(&confirmation.cancel_button_title, field_values)
        ));
    }
    Some(lines.join("\n"))
}

pub fn action_arguments(
    action: &ActionView,
    field_values: &BTreeMap<String, String>,
) -> Vec<String> {
    let mut arguments = action
        .arguments
        .iter()
        .map(|argument| interpolate_fields(argument, field_values))
        .collect::<Vec<_>>();
    for group in &action.optional_arguments {
        if missing_placeholders(group, field_values).is_empty() {
            arguments.extend(
                group
                    .iter()
                    .map(|argument| interpolate_fields(argument, field_values)),
            );
        }
    }
    arguments
}

pub fn prepare_setup_command(step: &SetupStepView, bundle_root: &Path) -> Result<PreparedCommand> {
    let mut command = setup_command(step, bundle_root)?;
    command.title = step.label.clone();
    command.env = step.environment.clone();
    add_bundle_environment(&mut command.env, bundle_root);
    Ok(command)
}

pub fn run_data_source(
    data_source: &DataSourceView,
    field_values: &BTreeMap<String, String>,
    bundle_root: &Path,
) -> Result<Value> {
    let executable = resolve_bundle_path(&data_source.path, bundle_root);
    let arguments = data_source
        .arguments
        .iter()
        .map(|argument| interpolate_fields(argument, field_values))
        .collect::<Vec<_>>();
    let cwd = data_source
        .working_directory
        .as_deref()
        .map(|path| resolve_bundle_path(path, bundle_root))
        .unwrap_or_else(|| bundle_root.to_path_buf());
    let mut env = data_source.environment.clone();
    add_context_environment(&mut env, field_values, bundle_root);
    env.insert("GUI_FOR_CLI_DATA_SOURCE".to_string(), "1".to_string());

    let output = run_process(
        &executable.display().to_string(),
        &arguments,
        &cwd,
        &env,
        Some(DATA_SOURCE_TIMEOUT),
    )
    .with_context(|| format!("run data source {}", data_source.path))?;
    if output.timed_out {
        return Err(anyhow!(
            "data source {} timed out after {} seconds",
            data_source.path,
            DATA_SOURCE_TIMEOUT.as_secs()
        ));
    }
    if !output.status.success() {
        return Err(anyhow!(
            "data source {} exited {}: {}",
            data_source.path,
            output.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&output.stderr.data).trim()
        ));
    }
    if output.stdout.truncated_bytes > 0 {
        return Err(anyhow!(
            "data source {} stdout exceeded {} bytes",
            data_source.path,
            STDOUT_LIMIT
        ));
    }
    serde_json::from_slice(&output.stdout.data)
        .with_context(|| format!("parse data source JSON from {}", data_source.path))
}

pub fn interpolate_fields(value: &str, field_values: &BTreeMap<String, String>) -> String {
    let mut rendered = String::new();
    let mut rest = value;
    while let Some(start) = rest.find("{{") {
        rendered.push_str(&rest[..start]);
        let after_start = &rest[start + 2..];
        if let Some(end) = after_start.find("}}") {
            let placeholder = after_start[..end].trim();
            rendered.push_str(
                field_values
                    .get(placeholder)
                    .map(String::as_str)
                    .unwrap_or(""),
            );
            rest = &after_start[end + 2..];
        } else {
            rendered.push_str(&rest[start..]);
            rest = "";
        }
    }
    rendered.push_str(rest);
    rendered
}

pub fn display_command(executable: &str, arguments: &[String]) -> String {
    std::iter::once(shell_quote(executable))
        .chain(arguments.iter().map(|argument| shell_quote(argument)))
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn run_prepared_command_tracked(
    command: PreparedCommand,
    terminal_id: u64,
    registry: RunningProcessRegistry,
) -> String {
    run_command_text_with_registry(
        &command.title,
        &command.executable,
        &command.arguments,
        &command.cwd,
        &command.env,
        &command.exit_code_reference,
        Some(registry),
        terminal_id,
    )
}

fn run_command_text_with_registry(
    title: &str,
    executable: &str,
    arguments: &[String],
    cwd: &Path,
    env: &BTreeMap<String, String>,
    exit_code_reference: &BTreeMap<i32, ExitCodeReferenceView>,
    registry: Option<RunningProcessRegistry>,
    registry_id: u64,
) -> String {
    let mut output = format!("$ {}\n", display_command(executable, arguments));
    match run_process_with_registry(executable, arguments, cwd, env, None, registry, registry_id) {
        Ok(result) => {
            output.push_str(&stream_text(&result.stdout, "stdout"));
            output.push_str(&stream_text(&result.stderr, "stderr"));
            let status = result.status.code().unwrap_or(-1);
            if result.timed_out {
                output.push_str("\n[timeout]");
            }
            if status != 0 {
                let explanation = explain(status, exit_code_reference);
                output.push_str(&format!(
                    "\n[exit {}] {}\n[exit explanation] {}",
                    explanation.severity, explanation.title, explanation.summary
                ));
            }
            output.push_str(&format!("\n[{title} exit {status}]"));
        }
        Err(error) => {
            output.push_str(&format!("Could not run {title}: {error}"));
        }
    }
    output
}

struct ProcessResult {
    status: std::process::ExitStatus,
    stdout: CapturedStream,
    stderr: CapturedStream,
    timed_out: bool,
}

struct CapturedStream {
    data: Vec<u8>,
    truncated_bytes: usize,
}

fn run_process(
    executable: &str,
    arguments: &[String],
    cwd: &Path,
    env: &BTreeMap<String, String>,
    timeout: Option<Duration>,
) -> Result<ProcessResult> {
    run_process_with_registry(executable, arguments, cwd, env, timeout, None, 0)
}

fn run_process_with_registry(
    executable: &str,
    arguments: &[String],
    cwd: &Path,
    env: &BTreeMap<String, String>,
    timeout: Option<Duration>,
    registry: Option<RunningProcessRegistry>,
    registry_id: u64,
) -> Result<ProcessResult> {
    let mut command = Command::new(executable);
    command
        .args(arguments)
        .current_dir(cwd)
        .envs(env)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(unix)]
    {
        command.process_group(0);
    }
    let mut child = command
        .spawn()
        .with_context(|| format!("spawn {executable}"))?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| anyhow!("capture stdout for {executable}"))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| anyhow!("capture stderr for {executable}"))?;
    let stdout_reader = thread::spawn(move || read_stream_limited(stdout, STDOUT_LIMIT));
    let stderr_reader = thread::spawn(move || read_stream_limited(stderr, STDERR_LIMIT));
    let child = Arc::new(Mutex::new(child));
    if let Some(registry) = &registry {
        registry
            .lock()
            .map_err(|_| anyhow!("running process registry is unavailable"))?
            .insert(registry_id, child.clone());
    }
    let started = Instant::now();
    let timed_out = loop {
        if child
            .lock()
            .map_err(|_| anyhow!("running process handle is unavailable"))?
            .try_wait()?
            .is_some()
        {
            break false;
        }
        if timeout.is_some_and(|limit| started.elapsed() >= limit) {
            if let Ok(mut child) = child.lock() {
                let _ = kill_child_tree(&mut child);
            }
            break true;
        }
        thread::sleep(Duration::from_millis(20));
    };
    let status = child
        .lock()
        .map_err(|_| anyhow!("running process handle is unavailable"))?
        .wait()
        .with_context(|| format!("wait for {executable}"))?;
    if let Some(registry) = &registry {
        if let Ok(mut registry) = registry.lock() {
            registry.remove(&registry_id);
        }
    }
    let stdout = stdout_reader
        .join()
        .map_err(|_| anyhow!("stdout reader panicked for {executable}"))?
        .with_context(|| format!("read stdout from {executable}"))?;
    let stderr = stderr_reader
        .join()
        .map_err(|_| anyhow!("stderr reader panicked for {executable}"))?
        .with_context(|| format!("read stderr from {executable}"))?;
    Ok(ProcessResult {
        status,
        stdout,
        stderr,
        timed_out,
    })
}

fn read_stream_limited(mut reader: impl Read, limit: usize) -> Result<CapturedStream> {
    let mut data = Vec::new();
    let mut truncated_bytes = 0;
    let mut buffer = [0_u8; 8192];
    loop {
        let read = reader.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        let remaining = limit.saturating_sub(data.len());
        let kept = read.min(remaining);
        if kept > 0 {
            data.extend_from_slice(&buffer[..kept]);
        }
        truncated_bytes += read - kept;
    }
    Ok(CapturedStream {
        data,
        truncated_bytes,
    })
}

fn stream_text(stream: &CapturedStream, stream_name: &str) -> String {
    let mut text = String::from_utf8_lossy(&stream.data).to_string();
    if stream.truncated_bytes > 0 {
        text.push_str(&format!(
            "\n[{stream_name} truncated: {} bytes omitted]",
            stream.truncated_bytes
        ));
    }
    text
}

pub type RunningProcessRegistry = Arc<Mutex<BTreeMap<u64, Arc<Mutex<Child>>>>>;

pub fn running_process_registry() -> RunningProcessRegistry {
    Arc::new(Mutex::new(BTreeMap::new()))
}

pub fn cancel_running_process(terminal_id: u64, registry: &RunningProcessRegistry) -> Result<bool> {
    let child = registry
        .lock()
        .map_err(|_| anyhow!("running process registry is unavailable"))?
        .get(&terminal_id)
        .cloned();
    let Some(child) = child else {
        return Ok(false);
    };
    let mut child = child
        .lock()
        .map_err(|_| anyhow!("running process handle is unavailable"))?;
    kill_child_tree(&mut child)
        .with_context(|| format!("cancel process tree for terminal tab {terminal_id}"))?;
    Ok(true)
}

fn kill_child_tree(child: &mut Child) -> Result<()> {
    #[cfg(unix)]
    {
        let process_group = format!("-{}", child.id());
        let status = Command::new("/bin/kill")
            .args(["-TERM", process_group.as_str()])
            .status()
            .context("send TERM to process group")?;
        if status.success() {
            return Ok(());
        }
    }
    child.kill().context("kill child process")
}

#[derive(Debug, Clone)]
pub struct PreparedCommand {
    pub title: String,
    executable: String,
    arguments: Vec<String>,
    cwd: PathBuf,
    env: BTreeMap<String, String>,
    exit_code_reference: BTreeMap<i32, ExitCodeReferenceView>,
}

impl PreparedCommand {
    pub fn display(&self) -> String {
        display_command(&self.executable, &self.arguments)
    }

    pub fn with_exit_code_reference(
        mut self,
        exit_code_reference: BTreeMap<i32, ExitCodeReferenceView>,
    ) -> Self {
        self.exit_code_reference = exit_code_reference;
        self
    }
}

fn setup_command(step: &SetupStepView, bundle_root: &Path) -> Result<PreparedCommand> {
    let cwd = step
        .working_directory
        .as_deref()
        .map(|path| resolve_bundle_path(path, bundle_root))
        .unwrap_or_else(|| bundle_root.to_path_buf());
    let value = if step.value.is_empty() {
        String::new()
    } else {
        step.value.clone()
    };
    let arguments = step.arguments.clone();
    let command = match step.kind.as_str() {
        "pathTool" => {
            if cfg!(windows) {
                PreparedCommand {
                    title: step.label.clone(),
                    executable: "where".to_string(),
                    arguments: vec![value],
                    cwd,
                    env: BTreeMap::new(),
                    exit_code_reference: BTreeMap::new(),
                }
            } else {
                PreparedCommand {
                    title: step.label.clone(),
                    executable: "/usr/bin/env".to_string(),
                    arguments: vec!["which".to_string(), value],
                    cwd,
                    env: BTreeMap::new(),
                    exit_code_reference: BTreeMap::new(),
                }
            }
        }
        "homebrewPackage" => PreparedCommand {
            title: step.label.clone(),
            executable: "/usr/bin/env".to_string(),
            arguments: vec!["brew".to_string(), "list".to_string(), value],
            cwd,
            env: BTreeMap::new(),
            exit_code_reference: BTreeMap::new(),
        },
        "bundledScript" | "setupScript" => PreparedCommand {
            title: step.label.clone(),
            executable: shell_executable(),
            arguments: std::iter::once(
                resolve_bundle_path(&value, bundle_root)
                    .display()
                    .to_string(),
            )
            .chain(arguments)
            .collect(),
            cwd,
            env: BTreeMap::new(),
            exit_code_reference: BTreeMap::new(),
        },
        "pixiInstall" => PreparedCommand {
            title: step.label.clone(),
            executable: "/usr/bin/env".to_string(),
            arguments: std::iter::once("pixi".to_string())
                .chain(std::iter::once("install".to_string()))
                .chain(arguments)
                .collect(),
            cwd,
            env: BTreeMap::new(),
            exit_code_reference: BTreeMap::new(),
        },
        "pixiRun" => PreparedCommand {
            title: step.label.clone(),
            executable: "/usr/bin/env".to_string(),
            arguments: std::iter::once("pixi".to_string())
                .chain(std::iter::once("run".to_string()))
                .chain(std::iter::once(value))
                .chain(arguments)
                .collect(),
            cwd,
            env: BTreeMap::new(),
            exit_code_reference: BTreeMap::new(),
        },
        _ => return Err(anyhow!("unsupported setup step kind: {}", step.kind)),
    };
    Ok(command)
}

fn resolve_bundle_path(value: &str, bundle_root: &Path) -> PathBuf {
    let path = PathBuf::from(value);
    if path.is_absolute() {
        path
    } else {
        bundle_root.join(path)
    }
}

fn shell_executable() -> String {
    if cfg!(windows) {
        "sh".to_string()
    } else {
        "/bin/sh".to_string()
    }
}

fn add_context_environment(
    env: &mut BTreeMap<String, String>,
    field_values: &BTreeMap<String, String>,
    bundle_root: &Path,
) {
    add_bundle_environment(env, bundle_root);
    for (key, value) in field_values {
        env.insert(
            format!("GUI_FOR_CLI_FIELD_{}", environment_key(key)),
            value.clone(),
        );
        env.insert(
            format!("GUI_FOR_CLI_CONFIG_{}", environment_key(key)),
            value.clone(),
        );
    }
}

fn add_bundle_environment(env: &mut BTreeMap<String, String>, bundle_root: &Path) {
    env.insert(
        "GUI_FOR_CLI_BUNDLE_ROOT".to_string(),
        bundle_root.display().to_string(),
    );
    env.insert(
        "GUI_FOR_CLI_BUNDLE_WORKSPACE".to_string(),
        bundle_root.display().to_string(),
    );
}

fn environment_key(value: &str) -> String {
    value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() {
                character.to_ascii_uppercase()
            } else {
                '_'
            }
        })
        .collect()
}

fn missing_required_placeholders(
    executable: &str,
    arguments: &[String],
    field_values: &BTreeMap<String, String>,
) -> Vec<String> {
    missing_placeholders(
        &std::iter::once(executable.to_string())
            .chain(arguments.iter().cloned())
            .collect::<Vec<_>>(),
        field_values,
    )
}

fn missing_placeholders(values: &[String], field_values: &BTreeMap<String, String>) -> Vec<String> {
    let mut missing = Vec::new();
    for value in values {
        let mut rest = value.as_str();
        while let Some(start) = rest.find("{{") {
            let after_start = &rest[start + 2..];
            let Some(end) = after_start.find("}}") else {
                break;
            };
            let placeholder = after_start[..end].trim();
            let is_builtin = matches!(placeholder, "bundleRoot" | "bundleWorkspace" | "home");
            let has_value = field_values
                .get(placeholder)
                .is_some_and(|value| !value.trim().is_empty());
            if !is_builtin && !has_value && !missing.iter().any(|value| value == placeholder) {
                missing.push(placeholder.to_string());
            }
            rest = &after_start[end + 2..];
        }
    }
    missing
}

fn condition_matches(
    condition: &crate::bundle::ActionCondition,
    field_values: &BTreeMap<String, String>,
) -> bool {
    let value = context_value(&condition.placeholder, field_values);
    let trimmed = value.trim();
    if condition
        .exists
        .is_some_and(|exists| exists != !trimmed.is_empty())
    {
        return false;
    }
    if let Some(equals) = &condition.equals {
        if trimmed != interpolate_fields(equals, field_values) {
            return false;
        }
    }
    if let Some(not_equals) = &condition.not_equals {
        if trimmed == interpolate_fields(not_equals, field_values) {
            return false;
        }
    }
    if !condition.in_values.is_empty()
        && !condition
            .in_values
            .iter()
            .map(|value| interpolate_fields(value, field_values))
            .any(|value| value == trimmed)
    {
        return false;
    }
    if condition
        .not_in_values
        .iter()
        .map(|value| interpolate_fields(value, field_values))
        .any(|value| value == trimmed)
    {
        return false;
    }
    numeric_condition(
        &condition.less_than,
        trimmed,
        field_values,
        |left, right| left < right,
    ) && numeric_condition(
        &condition.less_than_or_equal,
        trimmed,
        field_values,
        |left, right| left <= right,
    ) && numeric_condition(
        &condition.greater_than,
        trimmed,
        field_values,
        |left, right| left > right,
    ) && numeric_condition(
        &condition.greater_than_or_equal,
        trimmed,
        field_values,
        |left, right| left >= right,
    )
}

fn numeric_condition(
    expected: &Option<String>,
    actual: &str,
    field_values: &BTreeMap<String, String>,
    op: impl Fn(f64, f64) -> bool,
) -> bool {
    let Some(expected) = expected else {
        return true;
    };
    let Ok(actual) = actual.parse::<f64>() else {
        return false;
    };
    let rendered = interpolate_fields(expected, field_values);
    let Ok(expected) = rendered.parse::<f64>() else {
        return false;
    };
    op(actual, expected)
}

fn context_value(placeholder: &str, field_values: &BTreeMap<String, String>) -> String {
    if let Some(row_value) = placeholder.strip_prefix("row.") {
        return field_values.get(row_value).cloned().unwrap_or_default();
    }
    if let Some(config_value) = placeholder.strip_prefix("config.") {
        return field_values.get(config_value).cloned().unwrap_or_default();
    }
    field_values.get(placeholder).cloned().unwrap_or_default()
}

fn readable_placeholder(placeholder: &str) -> String {
    placeholder
        .strip_prefix("row.")
        .or_else(|| placeholder.strip_prefix("config."))
        .unwrap_or(placeholder)
        .replace(['_', '.', '-'], " ")
}

fn shell_quote(value: &str) -> String {
    if value
        .chars()
        .all(|character| character.is_ascii_alphanumeric() || "_./:-".contains(character))
    {
        value.to_string()
    } else {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn optional_arguments_only_render_when_values_are_present() {
        let action = ActionView {
            id: "align".to_string(),
            title: "Align".to_string(),
            role: "primary".to_string(),
            executable: "tool".to_string(),
            arguments: vec!["--input".to_string(), "{{input}}".to_string()],
            optional_arguments: vec![vec!["--out".to_string(), "{{out_dir}}".to_string()]],
            environment: BTreeMap::new(),
            working_directory: None,
            visible_when: Vec::new(),
            disabled_when: Vec::new(),
            disabled_tooltip: String::new(),
            confirmation: None,
        };
        let mut values = BTreeMap::from([("input".to_string(), "reads.fastq".to_string())]);
        assert_eq!(
            action_arguments(&action, &values),
            vec!["--input", "reads.fastq"]
        );

        values.insert("out_dir".to_string(), "results".to_string());
        assert_eq!(
            action_arguments(&action, &values),
            vec!["--input", "reads.fastq", "--out", "results"]
        );
    }

    #[test]
    fn action_unavailable_reason_reports_missing_required_values() {
        let action = ActionView {
            id: "align".to_string(),
            title: "Align".to_string(),
            role: "primary".to_string(),
            executable: "tool".to_string(),
            arguments: vec!["--input".to_string(), "{{fastq_r1}}".to_string()],
            optional_arguments: vec![vec!["--out".to_string(), "{{out_dir}}".to_string()]],
            environment: BTreeMap::new(),
            working_directory: None,
            visible_when: Vec::new(),
            disabled_when: Vec::new(),
            disabled_tooltip: String::new(),
            confirmation: None,
        };

        assert_eq!(
            action_unavailable_reason(&action, &BTreeMap::new()),
            Some("Fill required values: fastq r1".to_string())
        );
    }
}
