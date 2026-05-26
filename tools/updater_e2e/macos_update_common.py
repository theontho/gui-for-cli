from __future__ import annotations

import contextlib
import json
import plistlib
import shutil
import subprocess
import tarfile
import urllib.request
from pathlib import Path

try:
    from .macos_update_types import AppMetadata, DOWNLOAD_TIMEOUT_SECONDS, REPO
except ImportError:  # pragma: no cover - script execution path
    from macos_update_types import AppMetadata, DOWNLOAD_TIMEOUT_SECONDS, REPO


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


def download(url: str, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        return path
    print(f"Downloading {url}")
    with urllib.request.urlopen(url, timeout=DOWNLOAD_TIMEOUT_SECONDS) as response, path.open("wb") as file:
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


def extract_tar_data(tar: tarfile.TarFile, dest: Path) -> None:
    if hasattr(tarfile, "data_filter"):
        tar.extractall(dest, filter="data")
        return
    dest_root = dest.resolve()
    for member in tar.getmembers():
        target = (dest / member.name).resolve(strict=False)
        if not target.is_relative_to(dest_root):
            raise RuntimeError(f"Refusing to extract tar member outside destination: {member.name}")
        if member.isdev():
            raise RuntimeError(f"Refusing to extract device tar member: {member.name}")
        if member.issym() or member.islnk():
            link_target = Path(member.linkname)
            if not link_target.is_absolute():
                link_target = target.parent / link_target
            if not link_target.resolve(strict=False).is_relative_to(dest_root):
                raise RuntimeError(f"Refusing to extract tar link outside destination: {member.name}")
    tar.extractall(dest)


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
