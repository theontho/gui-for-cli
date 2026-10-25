//! macOS: after Uninstall removes what setup installed, the running app moves itself to the Trash,
//! as dragging it there would, so nothing of the app is left behind.
// Built elsewhere only for its tests.
#![cfg_attr(not(target_os = "macos"), allow(dead_code))]

use std::{
    fs,
    path::{Path, PathBuf},
};

/// WebKit and AppKit keep these per-app folders under ~/Library, outside the app's data folder.
const LIBRARY_DATA_FOLDERS: &[&str] = &["WebKit", "HTTPStorages", "Saved Application State"];

pub(crate) fn remove_library_data(identifier: &str) -> Result<(), String> {
    let Some(library) = home_dir().map(|home| home.join("Library")) else {
        return Ok(());
    };
    for folder in LIBRARY_DATA_FOLDERS {
        let name = if *folder == "Saved Application State" {
            format!("{identifier}.savedState")
        } else {
            identifier.to_string()
        };
        remove_dir_if_present(&library.join(folder).join(name))?;
    }
    Ok(())
}

/// Moves the running `.app` into ~/.Trash and returns where it went. Fails when the app is not on
/// the home folder's volume (a mounted DMG, a translocated or external copy): the user drags it.
pub(crate) fn move_running_app_to_trash() -> Result<PathBuf, String> {
    let executable = std::env::current_exe()
        .map_err(|error| format!("could not find the running app: {error}"))?;
    let app = app_bundle(&executable)
        .ok_or_else(|| format!("{} is not inside an app bundle", executable.display()))?;
    let trash = home_dir()
        .map(|home| home.join(".Trash"))
        .ok_or("could not find the home folder")?;
    fs::create_dir_all(&trash)
        .map_err(|error| format!("could not open {}: {error}", trash.display()))?;
    let destination = free_trash_path(&trash, &app);
    fs::rename(&app, &destination).map_err(|error| {
        format!(
            "could not move {} to the Trash ({error}); drag it to the Trash instead",
            app.display()
        )
    })?;
    Ok(destination)
}

/// `.../Name.app/Contents/MacOS/binary` -> `.../Name.app`.
fn app_bundle(executable: &Path) -> Option<PathBuf> {
    let app = executable.parent()?.parent()?.parent()?;
    (app.extension()? == "app").then(|| app.to_path_buf())
}

/// `Name.app`, or `Name 2.app`, `Name 3.app`, ... when the Trash already holds one.
fn free_trash_path(trash: &Path, app: &Path) -> PathBuf {
    let stem = app
        .file_stem()
        .map(|stem| stem.to_string_lossy().into_owned())
        .unwrap_or_default();
    let mut candidate = trash.join(format!("{stem}.app"));
    let mut copy = 2;
    while candidate.exists() {
        candidate = trash.join(format!("{stem} {copy}.app"));
        copy += 1;
    }
    candidate
}

fn remove_dir_if_present(path: &Path) -> Result<(), String> {
    match fs::remove_dir_all(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(format!("could not remove {}: {error}", path.display())),
    }
}

fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .filter(|home| !home.is_empty())
        .map(PathBuf::from)
}

#[cfg(test)]
mod tests {
    use super::{app_bundle, free_trash_path};
    use std::path::Path;

    #[test]
    fn finds_the_app_bundle_of_the_executable() {
        assert_eq!(
            app_bundle(Path::new(
                "/Applications/WGSExtract.app/Contents/MacOS/wgsextract"
            )),
            Some(Path::new("/Applications/WGSExtract.app").to_path_buf())
        );
        assert_eq!(app_bundle(Path::new("/usr/local/bin/tool/x/y")), None);
    }

    #[test]
    fn picks_a_free_name_in_the_trash() {
        let trash = std::env::temp_dir().join(format!("gfc-trash-test-{}", std::process::id()));
        std::fs::create_dir_all(trash.join("Tool.app")).unwrap();
        let app = Path::new("/Applications/Tool.app");
        assert_eq!(free_trash_path(&trash, app), trash.join("Tool 2.app"));
        std::fs::remove_dir_all(&trash).unwrap();
    }
}
