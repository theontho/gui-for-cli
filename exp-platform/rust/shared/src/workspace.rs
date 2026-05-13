use anyhow::{Context, Result, anyhow};
use serde::Deserialize;
use serde_json::Value;
use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Deserialize)]
struct ManifestHeader {
    id: String,
    #[serde(default)]
    pages: Vec<Value>,
}

pub fn prepare_bundle_workspace(source_root: &Path) -> Result<(PathBuf, Vec<String>)> {
    let source_root = source_root
        .canonicalize()
        .with_context(|| format!("resolve {}", source_root.display()))?;
    let manifest = read_manifest(&source_root)?;
    let workspace_root = bundle_workspace_directory(&manifest.id)?;
    fs::create_dir_all(&workspace_root)
        .with_context(|| format!("create {}", workspace_root.display()))?;

    let preserved_names = preserved_workspace_names(&source_root, &workspace_root, &manifest)?;
    let source_names = source_entry_names(&source_root)?;
    for entry in fs::read_dir(&workspace_root)
        .with_context(|| format!("read {}", workspace_root.display()))?
    {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().to_string();
        if preserved_names.contains(&name) || source_names.contains(&name) {
            continue;
        }
        remove_path(&entry.path())?;
    }

    for entry in
        fs::read_dir(&source_root).with_context(|| format!("read {}", source_root.display()))?
    {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with('.') {
            continue;
        }
        let destination = workspace_root.join(&name);
        if preserved_names.contains(&name) && destination.exists() {
            continue;
        }
        remove_path(&destination)?;
        copy_recursively(&entry.path(), &destination, &source_root)?;
    }

    mark_scripts_executable(&workspace_root)?;
    Ok((
        workspace_root.clone(),
        vec![format!(
            "[bundle] Using persistent workspace: {}",
            workspace_root.display()
        )],
    ))
}

fn read_manifest(source_root: &Path) -> Result<ManifestHeader> {
    let manifest_path = source_root.join("manifest.json");
    let text = fs::read_to_string(&manifest_path)
        .with_context(|| format!("read {}", manifest_path.display()))?;
    serde_json::from_str(&text).with_context(|| format!("parse {}", manifest_path.display()))
}

fn source_entry_names(source_root: &Path) -> Result<BTreeSet<String>> {
    fs::read_dir(source_root)
        .with_context(|| format!("read {}", source_root.display()))?
        .map(|entry| {
            entry
                .map(|entry| entry.file_name().to_string_lossy().to_string())
                .map_err(anyhow::Error::from)
        })
        .filter(|name| !matches!(name, Ok(name) if name.starts_with('.')))
        .collect()
}

fn preserved_workspace_names(
    source_root: &Path,
    workspace_root: &Path,
    manifest: &ManifestHeader,
) -> Result<BTreeSet<String>> {
    let mut names = BTreeSet::from(["runtime".to_string(), "state.json".to_string()]);
    for page in manifest_pages(source_root, manifest)? {
        collect_config_roots(&page, workspace_root, &mut names);
    }
    Ok(names)
}

fn manifest_pages(source_root: &Path, manifest: &ManifestHeader) -> Result<Vec<Value>> {
    let mut pages = Vec::new();
    for page in &manifest.pages {
        match page {
            Value::String(file_name) => {
                if file_name.contains('/') || file_name.contains('\\') || file_name.contains("..") {
                    return Err(anyhow!("invalid page file name: {file_name}"));
                }
                let path = source_root.join("pages").join(file_name);
                let text = fs::read_to_string(&path)
                    .with_context(|| format!("read {}", path.display()))?;
                pages.push(
                    serde_json::from_str(&text)
                        .with_context(|| format!("parse {}", path.display()))?,
                );
            }
            value => pages.push(value.clone()),
        }
    }
    Ok(pages)
}

fn collect_config_roots(
    page: &Value,
    workspace_root: &Path,
    preserved_names: &mut BTreeSet<String>,
) {
    let Some(sections) = page.get("sections").and_then(Value::as_array) else {
        return;
    };
    for section in sections {
        let Some(controls) = section.get("controls").and_then(Value::as_array) else {
            continue;
        };
        for control in controls {
            let Some(path) = control
                .get("configFile")
                .and_then(|value| value.get("path"))
                .and_then(Value::as_str)
            else {
                continue;
            };
            if let Some(name) = top_level_workspace_name(path, workspace_root) {
                preserved_names.insert(name);
            }
        }
    }
}

fn top_level_workspace_name(path: &str, workspace_root: &Path) -> Option<String> {
    let expanded = path
        .replace("{{bundleRoot}}", &workspace_root.display().to_string())
        .replace("{{bundleWorkspace}}", &workspace_root.display().to_string());
    let resolved = if Path::new(&expanded).is_absolute() {
        PathBuf::from(expanded)
    } else {
        workspace_root.join(expanded)
    };
    let relative = resolved.strip_prefix(workspace_root).ok()?;
    relative
        .components()
        .next()
        .map(|component| component.as_os_str().to_string_lossy().to_string())
}

fn bundle_workspace_directory(bundle_id: &str) -> Result<PathBuf> {
    if let Ok(root) = std::env::var("GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT") {
        return Ok(PathBuf::from(root).join(safe_path_component(bundle_id)));
    }
    Ok(application_support_directory()?
        .join("gui-for-cli")
        .join("BundleWorkspaces")
        .join(safe_path_component(bundle_id)))
}

fn application_support_directory() -> Result<PathBuf> {
    if cfg!(target_os = "macos") {
        return Ok(home_dir()?.join("Library").join("Application Support"));
    }
    if cfg!(windows) {
        if let Ok(local_app_data) = std::env::var("LOCALAPPDATA") {
            return Ok(PathBuf::from(local_app_data));
        }
    }
    let data_root = std::env::var("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or(home_dir()?.join(".local").join("share"));
    Ok(data_root)
}

fn safe_path_component(value: &str) -> String {
    let sanitized = value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.') {
                character
            } else {
                '-'
            }
        })
        .collect::<String>()
        .trim_matches(['.', '-'])
        .to_string();
    if sanitized.is_empty() {
        "bundle".to_string()
    } else {
        sanitized
    }
}

fn copy_recursively(source: &Path, destination: &Path, allowed_root: &Path) -> Result<()> {
    let metadata =
        fs::symlink_metadata(source).with_context(|| format!("stat {}", source.display()))?;
    if metadata.file_type().is_symlink() {
        return Err(anyhow!(
            "bundle symlinks are not supported: {}",
            source.display()
        ));
    }
    let canonical_source = source
        .canonicalize()
        .with_context(|| format!("resolve {}", source.display()))?;
    if !canonical_source.starts_with(allowed_root) {
        return Err(anyhow!(
            "bundle path escapes source root: {}",
            source.display()
        ));
    }
    if metadata.is_dir() {
        fs::create_dir_all(destination)
            .with_context(|| format!("create {}", destination.display()))?;
        for entry in fs::read_dir(source).with_context(|| format!("read {}", source.display()))? {
            let entry = entry?;
            copy_recursively(
                &entry.path(),
                &destination.join(entry.file_name()),
                allowed_root,
            )?;
        }
    } else {
        if let Some(parent) = destination.parent() {
            fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
        }
        fs::copy(source, destination)
            .with_context(|| format!("copy {} to {}", source.display(), destination.display()))?;
        fs::set_permissions(destination, metadata.permissions())
            .with_context(|| format!("copy permissions to {}", destination.display()))?;
    }
    Ok(())
}

fn remove_path(path: &Path) -> Result<()> {
    if !path.exists() {
        return Ok(());
    }
    let metadata =
        fs::symlink_metadata(path).with_context(|| format!("stat {}", path.display()))?;
    if metadata.file_type().is_symlink() {
        fs::remove_file(path).with_context(|| format!("remove {}", path.display()))
    } else if metadata.is_dir() {
        fs::remove_dir_all(path).with_context(|| format!("remove {}", path.display()))
    } else {
        fs::remove_file(path).with_context(|| format!("remove {}", path.display()))
    }
}

fn mark_scripts_executable(root: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let scripts = root.join("scripts");
        if !scripts.is_dir() {
            return Ok(());
        }
        for entry in
            fs::read_dir(&scripts).with_context(|| format!("read {}", scripts.display()))?
        {
            let entry = entry?;
            let path = entry.path();
            if !path.is_file() {
                continue;
            }
            let mut permissions = fs::metadata(&path)?.permissions();
            permissions.set_mode(permissions.mode() | 0o755);
            fs::set_permissions(&path, permissions)
                .with_context(|| format!("mark executable {}", path.display()))?;
        }
    }
    Ok(())
}

fn home_dir() -> Result<PathBuf> {
    std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .map(PathBuf::from)
        .context("resolve home directory")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preserves_config_top_level_name() {
        let workspace = PathBuf::from("/workspace/gui-for-cli-workspace");
        assert_eq!(
            top_level_workspace_name("{{bundleWorkspace}}/settings/config.toml", &workspace),
            Some("settings".to_string())
        );
    }

    #[cfg(unix)]
    #[test]
    fn remove_path_unlinks_directory_symlink_without_removing_target() {
        use std::os::unix::fs::symlink;

        let root = test_workspace("remove-symlink");
        let target = root.join("target");
        let link = root.join("link");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&target).expect("create target");
        fs::write(target.join("file.txt"), "kept").expect("write target file");
        symlink(&target, &link).expect("create symlink");

        remove_path(&link).expect("remove symlink");

        assert!(!link.exists());
        assert_eq!(
            fs::read_to_string(target.join("file.txt")).expect("read target file"),
            "kept"
        );
        fs::remove_dir_all(root).expect("cleanup");
    }

    #[cfg(unix)]
    #[test]
    fn copy_recursively_rejects_symlink_sources() {
        use std::os::unix::fs::symlink;

        let root = test_workspace("copy-symlink");
        let source = root.join("source");
        let outside = root.join("outside");
        let destination = root.join("destination");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&source).expect("create source");
        fs::create_dir_all(&outside).expect("create outside");
        fs::write(outside.join("secret.txt"), "secret").expect("write outside file");
        symlink(&outside, source.join("link")).expect("create symlink");

        let allowed_root = source.canonicalize().expect("canonical source");
        let error = copy_recursively(&source.join("link"), &destination, &allowed_root)
            .expect_err("symlink should be rejected");

        assert!(error.to_string().contains("symlinks are not supported"));
        assert!(!destination.exists());
        fs::remove_dir_all(root).expect("cleanup");
    }

    fn test_workspace(name: &str) -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("target")
            .join("test-workspaces")
            .join(format!("{name}-{}", std::process::id()))
    }
}
