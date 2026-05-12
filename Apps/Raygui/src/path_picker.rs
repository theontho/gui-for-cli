use anyhow::{Context, Result, anyhow};
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PathPickerKind {
    File,
    Directory,
}

pub fn pick_path(
    control_id: &str,
    label: &str,
    current_value: &str,
    bundle_root: &Path,
) -> Result<Option<String>> {
    let kind = infer_kind(control_id, label, current_value);
    if cfg!(target_os = "macos") {
        pick_path_macos(kind, label, current_value, bundle_root)
    } else {
        Err(anyhow!(
            "native path picker is only implemented on macOS for the Raygui app"
        ))
    }
}

fn infer_kind(control_id: &str, label: &str, current_value: &str) -> PathPickerKind {
    let haystack = format!("{control_id} {label} {current_value}").to_lowercase();
    if [
        "dir",
        "directory",
        "folder",
        "library",
        "cache",
        "workspace",
        "out_",
    ]
    .iter()
    .any(|token| haystack.contains(token))
    {
        return PathPickerKind::Directory;
    }
    PathPickerKind::File
}

fn pick_path_macos(
    kind: PathPickerKind,
    label: &str,
    current_value: &str,
    bundle_root: &Path,
) -> Result<Option<String>> {
    let prompt = format!("Choose {label}");
    let default_location = default_location(current_value, bundle_root);
    let chooser = match kind {
        PathPickerKind::Directory => "choose folder",
        PathPickerKind::File => "choose file",
    };
    let script = format!(
        r#"try
set defaultLocation to POSIX file "{}"
set picked to {} with prompt "{}" default location defaultLocation
POSIX path of picked
on error number -128
""
end try"#,
        escape_applescript(&default_location.display().to_string()),
        chooser,
        escape_applescript(&prompt)
    );
    let output = Command::new("/usr/bin/osascript")
        .arg("-e")
        .arg(script)
        .output()
        .context("run macOS path picker")?;
    if !output.status.success() {
        return Err(anyhow!(
            "path picker failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    let picked = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if picked.is_empty() {
        Ok(None)
    } else {
        Ok(Some(picked))
    }
}

fn default_location(current_value: &str, bundle_root: &Path) -> PathBuf {
    let raw = current_value.trim();
    let candidate = if raw.is_empty() {
        bundle_root.to_path_buf()
    } else if let Some(rest) = raw.strip_prefix("~/") {
        home_dir().join(rest)
    } else {
        let path = PathBuf::from(raw);
        if path.is_absolute() {
            path
        } else {
            bundle_root.join(path)
        }
    };
    existing_directory(&candidate).unwrap_or_else(|| bundle_root.to_path_buf())
}

fn existing_directory(path: &Path) -> Option<PathBuf> {
    let mut candidate = if path.is_dir() {
        path.to_path_buf()
    } else {
        path.parent()?.to_path_buf()
    };
    loop {
        if candidate.is_dir() {
            return Some(candidate);
        }
        if !candidate.pop() {
            return None;
        }
    }
}

fn home_dir() -> PathBuf {
    std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/"))
}

fn escape_applescript(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}
