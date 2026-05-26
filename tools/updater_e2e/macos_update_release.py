from __future__ import annotations

import base64
import contextlib
import json
import os
import re
import subprocess
import tarfile
from pathlib import Path
from urllib.parse import urlparse

from defusedxml import ElementTree as ET

try:
    from .macos_update_common import (
        app_metadata,
        asset_url,
        current_tauri_platform,
        download,
        extract_tar_data,
        gh_json,
        read_info_plist,
        reset_dir,
        run,
        single_app,
    )
    from .macos_update_types import AppMetadata, ReleaseMetadata, SPARKLE_NS
except ImportError:  # pragma: no cover - script execution path
    from macos_update_common import (
        app_metadata,
        asset_url,
        current_tauri_platform,
        download,
        extract_tar_data,
        gh_json,
        read_info_plist,
        reset_dir,
        run,
        single_app,
    )
    from macos_update_types import AppMetadata, ReleaseMetadata, SPARKLE_NS


def prepare_release_metadata(repo: str, work_dir: Path) -> ReleaseMetadata:
    release_dir = reset_dir(work_dir / "release")
    release = gh_json(["release", "view", "--repo", repo, "--json", "tagName"])
    release_details = gh_json(["api", f"repos/{repo}/releases/tags/{release['tagName']}"])
    assets = release_asset_download_urls(release_details)

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
        extract_tar_data(tar, dest)
    app = single_app(dest)
    return app_metadata(app, read_info_plist(app))


def release_asset_download_urls(release: dict) -> dict[str, str]:
    assets: dict[str, str] = {}
    for asset in release.get("assets", []):
        name = asset.get("name")
        url = asset.get("browser_download_url")
        if isinstance(name, str) and isinstance(url, str) and url:
            assets[name] = url
    return assets


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
