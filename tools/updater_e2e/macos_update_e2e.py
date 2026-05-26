#!/usr/bin/env python3
"""Exercise macOS app updaters against the latest GitHub Release assets.

The harness builds local "old" apps with the same bundle identity as the
published release apps, triggers each updater through macOS Accessibility UI
scripting, and verifies that the app bundle version advances to the version
advertised by the real GitHub Release feed.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from .macos_update_build import old_swiftui_app, old_tauri_app
    from .macos_update_common import (
        ad_hoc_sign,
        app_metadata,
        asset_url,
        bundle_version,
        current_tauri_platform,
        download,
        extract_tar_data,
        gh_json,
        read_info_plist,
        reset_dir,
        reset_parent,
        run,
        single_app,
        temporary_dir,
        temporary_file,
        verify_old_app,
    )
    from .macos_update_flow import (
        applescript_string,
        click_update_menu,
        drive_update_until_version,
        finish_recording,
        process_exists,
        process_pid,
        register_app_bundle,
        relaunch_updated_app,
        run_update_flow,
        start_recording,
        stop_running_app,
        terminate_process,
        ui_contains_text,
        update_ui_state,
        wait_for_new_process,
        wait_for_process,
        wait_for_process_exit,
        wait_for_visible_version,
    )
    from .macos_update_release import (
        extract_tauri_public_key,
        inspect_swiftui_release_app,
        inspect_tauri_release_app,
        prepare_release_metadata,
        release_asset_download_urls,
    )
    from .macos_update_types import (
        DEFAULT_REPO,
        DOWNLOAD_TIMEOUT_SECONDS,
        OLD_VERSION,
        REPO,
        SPARKLE_NS,
        AppMetadata,
        ReleaseMetadata,
    )
except ImportError:  # pragma: no cover - script execution path
    from macos_update_build import old_swiftui_app, old_tauri_app
    from macos_update_common import (
        ad_hoc_sign,
        app_metadata,
        asset_url,
        bundle_version,
        current_tauri_platform,
        download,
        extract_tar_data,
        gh_json,
        read_info_plist,
        reset_dir,
        reset_parent,
        run,
        single_app,
        temporary_dir,
        temporary_file,
        verify_old_app,
    )
    from macos_update_flow import (
        applescript_string,
        click_update_menu,
        drive_update_until_version,
        finish_recording,
        process_exists,
        process_pid,
        register_app_bundle,
        relaunch_updated_app,
        run_update_flow,
        start_recording,
        stop_running_app,
        terminate_process,
        ui_contains_text,
        update_ui_state,
        wait_for_new_process,
        wait_for_process,
        wait_for_process_exit,
        wait_for_visible_version,
    )
    from macos_update_release import (
        extract_tauri_public_key,
        inspect_swiftui_release_app,
        inspect_tauri_release_app,
        prepare_release_metadata,
        release_asset_download_urls,
    )
    from macos_update_types import (
        DEFAULT_REPO,
        DOWNLOAD_TIMEOUT_SECONDS,
        OLD_VERSION,
        REPO,
        SPARKLE_NS,
        AppMetadata,
        ReleaseMetadata,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=DEFAULT_REPO, help="GitHub owner/repo to read releases from.")
    parser.add_argument("--work-dir", type=Path, default=REPO / "tmp/macos-updater-e2e")
    parser.add_argument("--old-version", default=OLD_VERSION)
    parser.add_argument("--surface", choices=("all", "swiftui", "webui"), default="all")
    parser.add_argument("--skip-build", action="store_true", help="Reuse previously built old apps in work-dir.")
    parser.add_argument("--video", action="store_true", help="Record screencapture videos for the update flows.")
    parser.add_argument("--video-seconds", type=int, default=180, help="Maximum seconds to wait for each recorded update flow.")
    parser.add_argument("--hold-seconds", type=float, default=3.0, help="Seconds to hold old/new version UI on screen.")
    parser.add_argument("--prompt-hold-seconds", type=float, default=2.0, help="Seconds to hold the update prompt before accepting it.")
    args = parser.parse_args()

    if sys.platform != "darwin":
        raise SystemExit("macOS updater E2E tests must run on macOS.")

    surfaces = ["swiftui", "webui"] if args.surface == "all" else [args.surface]
    args.work_dir.mkdir(parents=True, exist_ok=True)
    release = prepare_release_metadata(args.repo, args.work_dir)
    print(f"Latest release version: {release.version}")

    results: dict[str, Path | None] = {}
    if "swiftui" in surfaces:
        app = old_swiftui_app(args, release)
        results["swiftui"] = run_update_flow(
            surface="swiftui",
            app=app,
            expected_version=release.version,
            old_version=args.old_version,
            menu=(release.swiftui.app_name, "Check for Updates..."),
            buttons=("Install Update", "Install and Relaunch", "Relaunch"),
            work_dir=args.work_dir,
            record=args.video,
            video_seconds=args.video_seconds,
            hold_seconds=args.hold_seconds,
            prompt_hold_seconds=args.prompt_hold_seconds,
        )
    if "webui" in surfaces:
        app = old_tauri_app(args, release)
        results["webui"] = run_update_flow(
            surface="webui",
            app=app,
            expected_version=release.version,
            old_version=args.old_version,
            menu=(release.tauri.app_name, "Check for Updates..."),
            buttons=("Install and Restart", "Install Update", "Restart"),
            work_dir=args.work_dir,
            record=args.video,
            video_seconds=args.video_seconds,
            hold_seconds=args.hold_seconds,
            prompt_hold_seconds=args.prompt_hold_seconds,
        )

    print("Updater E2E results:")
    for surface, video in results.items():
        suffix = f" video={video}" if video else ""
        print(f"  {surface}: updated to {release.version}{suffix}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
