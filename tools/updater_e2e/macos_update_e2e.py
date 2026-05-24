#!/usr/bin/env python3
"""Exercise macOS app updaters against the latest GitHub Release assets.

The harness builds local "old" apps with the same bundle identity as the
published release apps, triggers each updater through macOS Accessibility UI
scripting, and verifies that the app bundle version advances to the version
advertised by the real GitHub Release feed.
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import json
import os
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import time
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse


REPO = Path(__file__).resolve().parents[2]
DEFAULT_REPO = "theontho/gui-for-cli"
OLD_VERSION = "0.0.1"
SPARKLE_NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


@dataclass(frozen=True)
class AppMetadata:
    app_name: str
    bundle_id: str
    version: str
    app_path: Path


@dataclass(frozen=True)
class ReleaseMetadata:
    version: str
    appcast_url: str
    latest_json_url: str
    sparkle_public_key: str
    tauri_public_key: str
    swiftui: AppMetadata
    tauri: AppMetadata


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
            menu=("Updates", "Check for Updates..."),
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


def prepare_release_metadata(repo: str, work_dir: Path) -> ReleaseMetadata:
    release_dir = reset_dir(work_dir / "release")
    release = gh_json(["release", "view", "--repo", repo, "--json", "tagName,assets"])
    assets = {asset["name"]: asset["url"] for asset in release["assets"]}

    appcast_url = asset_url(assets, "appcast.xml")
    latest_url = asset_url(assets, "latest.json")
    appcast_path = download(appcast_url, release_dir / "appcast.xml")
    latest_path = download(latest_url, release_dir / "latest.json")

    appcast = ET.parse(appcast_path)
    item = appcast.find("./channel/item")
    if item is None:
        raise RuntimeError("Sparkle appcast does not contain an item.")
    version = item.findtext(f"{SPARKLE_NS}version") or release["tagName"].lstrip("v")
    enclosure = item.find("enclosure")
    if enclosure is None or not enclosure.get("url"):
        raise RuntimeError("Sparkle appcast item is missing its enclosure URL.")

    swift_dmg = download(enclosure.get("url", ""), release_dir / Path(urlparse(enclosure.get("url", "")).path).name)
    swift_app = inspect_swiftui_release_app(swift_dmg, work_dir)

    latest = json.loads(latest_path.read_text(encoding="utf-8"))
    tauri_platform = current_tauri_platform(latest)
    tauri_asset_url = latest["platforms"][tauri_platform]["url"]
    tauri_archive = download(tauri_asset_url, release_dir / Path(urlparse(tauri_asset_url).path).name)
    tauri_app = inspect_tauri_release_app(tauri_archive, work_dir)

    return ReleaseMetadata(
        version=version,
        appcast_url=appcast_url,
        latest_json_url=latest_url,
        sparkle_public_key=read_info_plist(swift_app.app_path)["SUPublicEDKey"],
        tauri_public_key=extract_tauri_public_key(tauri_app.app_path),
        swiftui=swift_app,
        tauri=tauri_app,
    )


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


def run_update_flow(
    *,
    surface: str,
    app: Path,
    expected_version: str,
    old_version: str,
    menu: tuple[str, str],
    buttons: tuple[str, ...],
    work_dir: Path,
    record: bool,
    video_seconds: int,
    hold_seconds: float,
    prompt_hold_seconds: float,
) -> Path | None:
    video = work_dir / "videos" / f"{surface}-update.mov" if record else None
    if record:
        assert video is not None
        video.parent.mkdir(parents=True, exist_ok=True)
        video.unlink(missing_ok=True)
    process_name = app.stem
    stop_running_app(process_name)
    register_app_bundle(app)
    recorder = start_recording(video, video_seconds) if record else None
    try:
        run(["open", "-n", str(app)])
        old_pid = wait_for_process(process_name)
        wait_for_visible_version(process_name, old_version, timeout=30)
        time.sleep(hold_seconds)
        click_update_menu(process_name, menu[0], menu[1])
        time.sleep(prompt_hold_seconds)
        drive_update_until_version(
            app,
            expected_version,
            process_name,
            old_pid,
            buttons,
            timeout=video_seconds,
            relaunch_app=app if surface == "swiftui" else None,
        )
        wait_for_visible_version(process_name, expected_version, timeout=45)
        time.sleep(hold_seconds)
    finally:
        stop_running_app(process_name)
        if recorder is not None:
            finish_recording(recorder, video, video_seconds)
    return video


def inspect_swiftui_release_app(dmg: Path, work_dir: Path) -> AppMetadata:
    mount = reset_dir(work_dir / "mount-swiftui")
    run(["hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint", str(mount), str(dmg)])
    try:
        app = single_app(mount)
        info = read_info_plist(app)
        staged = reset_dir(work_dir / "release-swiftui") / app.name
        shutil.copytree(app, staged, symlinks=True)
        return app_metadata(staged, info)
    finally:
        run(["hdiutil", "detach", str(mount)], check=False)


def inspect_tauri_release_app(archive: Path, work_dir: Path) -> AppMetadata:
    dest = reset_dir(work_dir / "release-tauri")
    with tarfile.open(archive) as tar:
        tar.extractall(dest, filter="data")
    app = single_app(dest)
    return app_metadata(app, read_info_plist(app))


def app_metadata(app: Path, info: dict) -> AppMetadata:
    return AppMetadata(
        app_name=info.get("CFBundleName") or app.stem,
        bundle_id=info["CFBundleIdentifier"],
        version=info["CFBundleShortVersionString"],
        app_path=app,
    )


def read_info_plist(app: Path) -> dict:
    with (app / "Contents/Info.plist").open("rb") as file:
        return plistlib.load(file)


def current_tauri_platform(latest: dict) -> str:
    machine = subprocess.check_output(["uname", "-m"], text=True).strip()
    arch = "aarch64" if machine == "arm64" else "x86_64"
    target = f"darwin-{arch}"
    if target not in latest["platforms"]:
        raise RuntimeError(f"latest.json does not contain {target}.")
    return target


def extract_tauri_public_key(app: Path) -> str:
    executable_dir = app / "Contents/MacOS"
    executables = [path for path in executable_dir.iterdir() if os.access(path, os.X_OK)]
    for executable in executables:
        strings = subprocess.run(["strings", str(executable)], text=True, capture_output=True, check=True).stdout
        for token in re.findall(r"dW50[A-Za-z0-9+/]*(?:={1,2})?", strings):
            with contextlib.suppress(Exception):
                decoded = base64.b64decode(token).decode("utf-8", "ignore")
                if "minisign public key" in decoded:
                    return token
    raise RuntimeError(f"Could not extract Tauri updater public key from {app}.")


def click_update_menu(process_name: str, menu_name: str, item_name: str) -> None:
    script = f"""
tell application "{process_name}" to activate
tell application "System Events"
  tell process "{process_name}"
    set frontmost to true
    delay 0.5
    tell menu bar 1
      click menu bar item "{menu_name}"
      delay 0.3
      if not (enabled of menu item "{item_name}" of menu 1 of menu bar item "{menu_name}") then error "Update menu item is disabled"
      click menu item "{item_name}" of menu 1 of menu bar item "{menu_name}"
    end tell
  end tell
end tell
"""
    run(["osascript", "-e", script])


def drive_update_until_version(
    app: Path,
    expected_version: str,
    process_name: str,
    old_pid: int,
    button_names: tuple[str, ...],
    timeout: int,
    relaunch_app: Path | None,
) -> None:
    deadline = time.monotonic() + timeout
    quoted = ", ".join(json.dumps(name) for name in button_names)
    script = f"""
set targetButtons to {{{quoted}}}
tell application "System Events"
  tell process "{process_name}"
    repeat with buttonName in targetButtons
      try
        click (first button of entire contents whose name is (buttonName as text))
        return true
      end try
    end repeat
  end tell
end tell
return false
"""
    last_state_log = 0.0
    while time.monotonic() < deadline:
        if bundle_version(app) == expected_version and process_pid(process_name) not in (0, old_pid):
            return
        if bundle_version(app) == expected_version and relaunch_app is not None:
            relaunch_updated_app(process_name, old_pid, relaunch_app)
            return
        result = subprocess.run(["osascript", "-e", script], text=True, capture_output=True, check=False)
        if result.stdout.strip() == "true" and bundle_version(app) == expected_version:
            if relaunch_app is not None:
                relaunch_updated_app(process_name, old_pid, relaunch_app)
            else:
                wait_for_process_exit(old_pid, timeout=30)
                wait_for_new_process(process_name, old_pid, timeout=45)
            return
        now = time.monotonic()
        if now - last_state_log > 10:
            print(update_ui_state(process_name))
            last_state_log = now
        subprocess.run(["osascript", "-e", 'tell application "System Events" to key code 36'], check=False)
        time.sleep(1)
    actual = bundle_version(app) if app.exists() else "<missing>"
    raise TimeoutError(f"{process_name} did not update to {expected_version}; current version is {actual}.")


def relaunch_updated_app(process_name: str, old_pid: int, app: Path) -> None:
    subprocess.run(["osascript", "-e", f'tell application "{process_name}" to quit'], check=False)
    wait_for_process_exit(old_pid, timeout=30)
    run(["open", "-n", str(app)])
    wait_for_new_process(process_name, old_pid, timeout=45)


def update_ui_state(process_name: str) -> str:
    script = f"""
tell application "System Events"
  if not (exists process {json.dumps(process_name)}) then return "process missing"
  tell process {json.dumps(process_name)}
    set output to "windows: " & (name of every window as text)
    repeat with appWindow in windows
      try
        set output to output & " | " & (name of appWindow as text) & " buttons: " & (name of every button of appWindow as text)
      end try
    end repeat
    return output
  end tell
end tell
"""
    result = subprocess.run(["osascript", "-e", script], text=True, capture_output=True, check=False)
    return result.stdout.strip() or result.stderr.strip()


def wait_for_visible_version(process_name: str, version: str, timeout: int) -> None:
    target = f"{version}"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if ui_contains_text(process_name, target):
            return
        time.sleep(0.5)
    print(f"Warning: {process_name} did not expose version {version} through Accessibility; continuing after bundle version verification.")


def ui_contains_text(process_name: str, target: str) -> bool:
    script = f"""
set targetText to {json.dumps(target)}
tell application "System Events"
  if not (exists process {json.dumps(process_name)}) then return false
  tell process {json.dumps(process_name)}
    try
      if (name of front window as text) contains targetText then return true
    end try
    repeat with uiElement in entire contents
      try
        if (value of uiElement as text) contains targetText then return true
      end try
      try
        if (name of uiElement as text) contains targetText then return true
      end try
      try
        if (description of uiElement as text) contains targetText then return true
      end try
    end repeat
  end tell
end tell
return false
"""
    result = subprocess.run(["osascript", "-e", script], text=True, capture_output=True, check=False)
    return result.stdout.strip() == "true"


def bundle_version(app: Path) -> str | None:
    if not app.exists():
        return None
    return read_info_plist(app).get("CFBundleShortVersionString")


def verify_old_app(app: Path, version: str, bundle_id: str) -> None:
    info = read_info_plist(app)
    if info.get("CFBundleShortVersionString") != version:
        raise RuntimeError(f"{app} was not built as old version {version}.")
    if info.get("CFBundleIdentifier") != bundle_id:
        raise RuntimeError(f"{app} bundle id does not match published updater identity.")


def start_recording(video: Path, seconds: int) -> subprocess.Popen:
    del seconds
    return subprocess.Popen(["screencapture", "-v", "-k", str(video)])


def finish_recording(process: subprocess.Popen, video: Path, seconds: int) -> None:
    if process.poll() is None:
        process.send_signal(signal.SIGINT)
    process.wait(timeout=seconds + 30)
    if process.returncode not in (0, -signal.SIGINT):
        raise RuntimeError(f"screencapture exited with code {process.returncode}.")
    if not video.exists() or video.stat().st_size == 0:
        raise RuntimeError(f"screencapture did not write a usable video at {video}.")


def wait_for_process(process_name: str, timeout: int = 30) -> int:
    deadline = time.monotonic() + timeout
    script = f'''
tell application "System Events"
  if not (exists process "{process_name}") then return false
  tell process "{process_name}"
    if (count of menu bars) = 0 then return false
    return unix id
  end tell
end tell
'''
    while time.monotonic() < deadline:
        result = subprocess.run(["osascript", "-e", script], text=True, capture_output=True, check=False)
        output = result.stdout.strip()
        if output.isdigit() and int(output) > 0:
            time.sleep(2)
            return int(output)
        time.sleep(0.5)
    raise TimeoutError(f"{process_name} did not launch.")


def process_pid(process_name: str) -> int:
    script = f'''
tell application "System Events"
  if not (exists process "{process_name}") then return 0
  tell process "{process_name}" to return unix id
end tell
'''
    result = subprocess.run(["osascript", "-e", script], text=True, capture_output=True, check=False)
    output = result.stdout.strip()
    return int(output) if output.isdigit() else 0


def wait_for_process_exit(pid: int, timeout: int) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not process_exists(pid):
            return
        time.sleep(0.5)
    raise TimeoutError(f"Old app process {pid} did not quit.")


def wait_for_new_process(process_name: str, old_pid: int, timeout: int) -> int:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        pid = process_pid(process_name)
        if pid and pid != old_pid:
            wait_for_process(process_name, timeout=10)
            return pid
        time.sleep(0.5)
    raise TimeoutError(f"{process_name} did not relaunch after update.")


def process_exists(pid: int) -> bool:
    if pid <= 0:
        return False
    return subprocess.run(["kill", "-0", str(pid)], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def stop_running_app(process_name: str) -> None:
    subprocess.run(["osascript", "-e", f'tell application "{process_name}" to quit'], check=False)
    time.sleep(1)
    pid = process_pid(process_name)
    if pid:
        terminate_process(pid, timeout=10)


def terminate_process(pid: int, timeout: int) -> None:
    subprocess.run(["kill", "-TERM", str(pid)], check=False)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not process_exists(pid):
            return
        time.sleep(0.5)
    print(f"Warning: process {pid} did not exit after SIGTERM; sending SIGKILL.")
    subprocess.run(["kill", "-KILL", str(pid)], check=False)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if not process_exists(pid):
            return
        time.sleep(0.25)
    print(f"Warning: process {pid} is still visible after SIGKILL.")


def register_app_bundle(app: Path) -> None:
    lsregister = Path(
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    )
    if lsregister.exists():
        run([str(lsregister), "-f", str(app)])


def download(url: str, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        return path
    print(f"Downloading {url}")
    with urllib.request.urlopen(url) as response, path.open("wb") as file:
        shutil.copyfileobj(response, file)
    return path


def asset_url(assets: dict[str, str], name: str) -> str:
    if name not in assets:
        raise RuntimeError(f"Latest GitHub Release is missing {name}.")
    return assets[name]


def single_app(root: Path) -> Path:
    apps = []
    for app in sorted(root.rglob("*.app")):
        relative_parts = app.relative_to(root).parts
        if "Contents" not in relative_parts[:-1]:
            apps.append(app)
    if len(apps) != 1:
        raise RuntimeError(f"Expected one .app under {root}, found {len(apps)}.")
    return apps[0]


def reset_dir(path: Path) -> Path:
    shutil.rmtree(path, ignore_errors=True)
    path.mkdir(parents=True, exist_ok=True)
    return path


def reset_parent(path: Path) -> None:
    shutil.rmtree(path.parent, ignore_errors=True)
    path.parent.mkdir(parents=True, exist_ok=True)


@contextlib.contextmanager
def temporary_file(path: Path, contents: str | None = None):
    existed = path.exists()
    previous = path.read_bytes() if existed else None
    path.parent.mkdir(parents=True, exist_ok=True)
    if contents is not None:
        path.write_text(contents, encoding="utf-8")
    try:
        yield
    finally:
        if existed:
            path.write_bytes(previous or b"")
        else:
            path.unlink(missing_ok=True)


@contextlib.contextmanager
def temporary_dir(path: Path):
    backup = None
    if path.exists() or path.is_symlink():
        backup = path.with_name(f"{path.name}.updater-e2e-backup")
        shutil.rmtree(backup, ignore_errors=True)
        path.rename(backup)
    try:
        yield
    finally:
        shutil.rmtree(path, ignore_errors=True)
        if backup is not None:
            backup.rename(path)


def ad_hoc_sign(app: Path) -> None:
    run(["codesign", "--force", "--deep", "--sign", "-", str(app)])
    run(["codesign", "--verify", "--deep", "--strict", str(app)])


def gh_json(args: list[str]) -> dict:
    result = subprocess.run(["gh", *args], cwd=REPO, text=True, capture_output=True, check=True)
    return json.loads(result.stdout)


def run(cmd: list[str], *, cwd: Path = REPO, check: bool = True) -> subprocess.CompletedProcess:
    print("+", " ".join(str(part) for part in cmd))
    return subprocess.run(cmd, cwd=cwd, check=check)


if __name__ == "__main__":
    raise SystemExit(main())
