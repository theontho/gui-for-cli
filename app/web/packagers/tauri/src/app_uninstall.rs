//! The app's own Uninstall, on Linux. A package manager removes the app's files but never what the
//! app's setup put in the user's home (the bundle's runtime, its Pixi environments, a reference
//! library), so the app removes those itself, as the macOS app's Uninstall does: the bundle's
//! uninstall steps (bundle-uninstall-cli.js, the Windows uninstaller's too), then the app's data.
//! The package itself is then removed with the package manager.

use std::{fs, process::Command, thread};

use tauri::{AppHandle, Manager, Runtime};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};

use crate::{backend::BackendProcess, child_process_path, menu::app_name, AppPaths};

pub(crate) const UNINSTALL_MENU_ID: &str = "uninstall-app";
/// Runs the uninstall at launch without asking, then quits (for automated lifecycle tests, as on macOS).
pub(crate) const AUTO_RUN_UNINSTALL_ENV: &str = "GUI_FOR_CLI_AUTO_RUN_UNINSTALL";

pub(crate) fn request_uninstall<R: Runtime>(app: &AppHandle<R>) {
    let app = app.clone();
    thread::spawn(move || {
        let name = app_name(&app);
        let confirmed = app
            .dialog()
            .message(format!(
                "This runs {name}'s uninstall steps and deletes everything {name} keeps in your \
                 home folder, including downloaded reference genomes and the settings in its \
                 workspace. Files you saved elsewhere are kept.\n\nAfterwards, remove the {name} \
                 package with your package manager (or delete its AppImage)."
            ))
            .title(format!("Uninstall {name}"))
            .kind(MessageDialogKind::Warning)
            .buttons(MessageDialogButtons::OkCancelCustom(
                "Uninstall".into(),
                "Cancel".into(),
            ))
            .blocking_show();
        if confirmed {
            run_uninstall(&app, true);
        }
    });
}

pub(crate) fn auto_run_uninstall<R: Runtime>(app: &AppHandle<R>) {
    let app = app.clone();
    thread::spawn(move || run_uninstall(&app, false));
}

fn run_uninstall<R: Runtime>(app: &AppHandle<R>, interactive: bool) {
    // Nothing of the bundle may run while its runtime is removed.
    app.state::<BackendProcess>().terminate();
    let outcome = remove_setup_and_data(app);
    if interactive {
        let name = app_name(app);
        let (kind, message) = match &outcome {
            Ok(()) => (
                MessageDialogKind::Info,
                format!(
                    "{name}'s data and what its setup installed were removed. To finish, remove \
                     the {name} package with your package manager (or delete its AppImage)."
                ),
            ),
            Err(error) => (
                MessageDialogKind::Error,
                format!("{name} could not be fully uninstalled: {error}."),
            ),
        };
        app.dialog()
            .message(message)
            .title(format!("Uninstall {name}"))
            .kind(kind)
            .buttons(MessageDialogButtons::Ok)
            .blocking_show();
    }
    if let Err(error) = &outcome {
        eprintln!("Uninstall failed: {error}");
    }
    app.exit(if outcome.is_ok() { 0 } else { 1 });
}

fn remove_setup_and_data<R: Runtime>(app: &AppHandle<R>) -> Result<(), String> {
    let paths = app.state::<AppPaths>();
    let script = paths
        .repo_root
        .join("app/dist/web/src/server/bundle-uninstall-cli.js");
    let status = Command::new(&paths.node_path)
        .arg(child_process_path(&script))
        .args([
            "--app-support-name",
            &paths.app_support_name,
            "--remove-app-data",
        ])
        .arg(child_process_path(&paths.bundle_root))
        .status()
        .map_err(|error| format!("could not run the uninstall steps: {error}"))?;
    if !status.success() {
        return Err(format!("the uninstall steps failed ({status})"));
    }
    // WebKit's caches, outside the data folder the steps removed.
    if let Ok(cache) = app.path().app_cache_dir() {
        match fs::remove_dir_all(&cache) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(format!("could not remove {}: {error}", cache.display())),
        }
    }
    Ok(())
}
