from __future__ import annotations

import argparse
import contextlib
import json
import shutil
from pathlib import Path

try:
    from .macos_update_common import ad_hoc_sign, reset_dir, reset_parent, run, temporary_dir, temporary_file, verify_old_app
    from .macos_update_types import REPO, ReleaseMetadata
except ImportError:  # pragma: no cover - script execution path
    from macos_update_common import ad_hoc_sign, reset_dir, reset_parent, run, temporary_dir, temporary_file, verify_old_app
    from macos_update_types import REPO, ReleaseMetadata


def old_swiftui_app(args: argparse.Namespace, release: ReleaseMetadata) -> Path:
    app = args.work_dir / "apps" / "swiftui" / f"{release.swiftui.app_name}.app"
    if args.skip_build and app.exists():
        verify_old_app(app, args.old_version, release.swiftui.bundle_id)
        return app

    derived = reset_dir(args.work_dir / "derived-swiftui")
    identity = {
        "embeddedBundlePath": "examples/WGSExtract",
        "displayName": release.swiftui.app_name,
        "productName": release.swiftui.app_name,
        "bundleIdentifierName": release.swiftui.app_name,
        "macBundleId": release.swiftui.bundle_id,
        "marketingVersion": args.old_version,
        "buildVersion": args.old_version,
        "sparkleEnableAutomaticChecks": False,
        "sparkleAppcastURL": release.appcast_url,
        "sparklePublicEDKey": release.sparkle_public_key,
    }
    with temporary_file(REPO / "tmp/app-identity.json", json.dumps(identity, indent=2) + "\n"):
        run(["python3", "tools/sync_apple_shared_resources.py"])
        run(["../../scripts/tuist.sh", "clean", "manifests"], cwd=REPO / "platform/apple")
        run(["../../scripts/tuist.sh", "generate", "--no-open"], cwd=REPO / "platform/apple")
        run(
            [
                "xcodebuild",
                "-workspace",
                "platform/apple/GUIForCLI.xcworkspace",
                "-scheme",
                "GUIForCLIMac",
                "-configuration",
                "Release",
                "-derivedDataPath",
                str(derived),
                "-destination",
                "platform=macOS",
                "build",
                "CODE_SIGNING_ALLOWED=NO",
            ]
        )
    built = derived / "Build/Products/Release" / app.name
    if not built.exists():
        raise RuntimeError(f"Expected built SwiftUI app at {built}.")
    reset_parent(app)
    shutil.copytree(built, app, symlinks=True)
    ad_hoc_sign(app)
    verify_old_app(app, args.old_version, release.swiftui.bundle_id)
    return app


def old_tauri_app(args: argparse.Namespace, release: ReleaseMetadata) -> Path:
    app = args.work_dir / "apps" / "tauri" / f"{release.tauri.app_name}.app"
    if args.skip_build and app.exists():
        verify_old_app(app, args.old_version, release.tauri.bundle_id)
        return app

    tauri_dir = REPO / "platform/typescript/web/packagers/tauri"
    resources = tauri_dir / "resources"
    embedded = resources / "EmbeddedBundle"
    branding = resources / "branding.json"
    config_path = REPO / "tmp/tauri.e2e.conf.json"
    bundle_root = tauri_dir / "target/release/bundle"
    reset_dir(bundle_root)

    with contextlib.ExitStack() as stack:
        stack.enter_context(temporary_dir(embedded))
        stack.enter_context(temporary_file(branding))
        stack.enter_context(temporary_file(config_path))
        shutil.copytree(REPO / "examples/WGSExtract", embedded, symlinks=True)
        branding.write_text(
            json.dumps(
                {
                    "appName": release.tauri.app_name,
                    "appVersion": args.old_version,
                    "appIdentifier": release.tauri.bundle_id,
                    "embeddedBundlePath": "examples/WGSExtract",
                    "embeddedBundleResourcePath": "examples/EmbeddedBundle",
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        config = json.loads((tauri_dir / "tauri.conf.json").read_text(encoding="utf-8"))
        config["productName"] = release.tauri.app_name
        config["version"] = args.old_version
        config["identifier"] = release.tauri.bundle_id
        config.setdefault("plugins", {})["updater"] = {
            "pubkey": release.tauri_public_key,
            "endpoints": [release.latest_json_url],
            "windows": {"installMode": "passive"},
        }
        config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")

        run(["npm", "--prefix", "platform/typescript", "run", "tauri:prepare-node"])
        run(["npm", "--prefix", "platform/typescript", "run", "build"])
        run(
            [
                "node",
                str(REPO / "platform/typescript/node_modules/@tauri-apps/cli/tauri.js"),
                "build",
                "-c",
                str(config_path),
            ],
            cwd=tauri_dir,
        )

    built = bundle_root / "macos" / app.name
    reset_parent(app)
    shutil.copytree(built, app, symlinks=True)
    ad_hoc_sign(app)
    verify_old_app(app, args.old_version, release.tauri.bundle_id)
    return app
