from __future__ import annotations

from pathlib import Path
from typing import Any
import gzip
import hashlib
import json
import os
import posixpath
import shutil
import sys
import tarfile
import zipfile

from .localization import load_localization, localize_manifest
from .models import LoadedBundle

ARCHIVE_CACHE_ROOT = Path("out/python-toga/archive-cache")


def load_bundle(
    bundle: str | Path,
    *,
    locale: str | None = None,
    repo_root: str | Path | None = None,
    workspace_root: str | Path | None = None,
) -> LoadedBundle:
    repo = Path(repo_root).resolve() if repo_root else find_repo_root(Path.cwd())
    bundle_root = _resolve_bundle_root(Path(bundle), repo)
    resources_root = repo / "resources"
    raw_manifest = _read_manifest(bundle_root)
    manifest_with_pages = _load_pages(bundle_root, raw_manifest)
    localization = load_localization(
        bundle_root,
        resources_root,
        locale,
        str(raw_manifest.get("defaultLocalizationCode") or "en"),
    )
    localized_manifest = localize_manifest(manifest_with_pages, localization.table)
    workspace = Path(workspace_root).expanduser().resolve() if workspace_root else default_workspace_root(localized_manifest)
    workspace.mkdir(parents=True, exist_ok=True)
    return LoadedBundle(
        bundle_root=bundle_root,
        workspace_root=workspace,
        resources_root=resources_root,
        manifest_raw=manifest_with_pages,
        manifest=localized_manifest,
        string_table=localization.table,
        localization_code=localization.code,
        localization_options=localization.available,
        layout_direction=localization.layout_direction,
    )


def find_repo_root(start: Path) -> Path:
    current = start.resolve()
    for candidate in (current, *current.parents):
        if (candidate / "examples").exists() and (candidate / "resources").exists():
            return candidate
    return current


def default_workspace_root(manifest: dict[str, Any]) -> Path:
    bundle_id = str(manifest.get("id") or "bundle").strip() or "bundle"
    safe = "".join(char if char.isalnum() or char in {"-", "_"} else "-" for char in bundle_id)
    return _user_data_root() / "gui-for-cli-python-toga" / "workspaces" / safe


def _user_data_root() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support"
    if os.name == "nt":
        return Path(
            os.environ.get("LOCALAPPDATA")
            or os.environ.get("APPDATA")
            or Path.home() / "AppData" / "Local"
        )
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")


def _resolve_bundle_root(bundle: Path, repo_root: Path) -> Path:
    candidate = bundle.expanduser()
    if not candidate.is_absolute():
        candidate = repo_root / candidate
    candidate = candidate.resolve()
    if candidate.is_file() and candidate.name == "manifest.json":
        return candidate.parent
    if candidate.is_dir():
        if (candidate / "manifest.json").exists():
            return candidate
        children = [child for child in candidate.iterdir() if child.is_dir() and (child / "manifest.json").exists()]
        if len(children) == 1:
            return children[0]
    if candidate.is_file() and _is_archive(candidate):
        return _extract_archive(candidate, repo_root)
    raise FileNotFoundError(f"Could not find manifest.json for bundle {bundle}")


def _is_archive(path: Path) -> bool:
    name = path.name.lower()
    return name.endswith((".zip", ".tar", ".tar.gz", ".tgz", ".gz"))


def _extract_archive(path: Path, repo_root: Path) -> Path:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(64 * 1024), b""):
            digest.update(chunk)
    cache = repo_root / ARCHIVE_CACHE_ROOT / digest.hexdigest()[:16]
    if (cache / "manifest.json").exists():
        return cache
    if cache.exists():
        shutil.rmtree(cache)
    cache.mkdir(parents=True, exist_ok=True)
    name = path.name.lower()
    if name.endswith(".zip"):
        with zipfile.ZipFile(path) as archive:
            _extract_zip_safely(archive, cache)
    elif name.endswith((".tar", ".tar.gz", ".tgz")):
        with tarfile.open(path) as archive:
            archive.extractall(cache, members=_safe_tar_members(archive, cache))
    elif name.endswith(".gz"):
        with gzip.open(path, "rb") as source:
            (cache / "manifest.json").write_bytes(source.read())
    if (cache / "manifest.json").exists():
        return cache
    children = [child for child in cache.iterdir() if child.is_dir() and (child / "manifest.json").exists()]
    if len(children) == 1:
        return children[0]
    raise FileNotFoundError(f"Archive {path} did not contain a supported bundle layout")


def _read_manifest(bundle_root: Path) -> dict[str, Any]:
    path = bundle_root / "manifest.json"
    with path.open("r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    if not isinstance(manifest, dict):
        raise ValueError("manifest.json must contain an object")
    return manifest


def _load_pages(bundle_root: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    loaded = _clone(manifest)
    pages = []
    pages_root = (bundle_root / "pages").resolve()
    for page_ref in manifest.get("pages", []) or []:
        if isinstance(page_ref, str):
            page_path = _require_path_inside(pages_root / page_ref, pages_root, "Page reference")
            with page_path.open("r", encoding="utf-8") as handle:
                page = json.load(handle)
            if not isinstance(page, dict):
                raise ValueError(f"Page {page_ref} must contain an object")
            pages.append(page)
        elif isinstance(page_ref, dict):
            pages.append(_clone(page_ref))
        else:
            raise ValueError(f"Unsupported page reference {page_ref!r}")
    loaded["pages"] = pages
    return loaded


def _clone(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _clone(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_clone(item) for item in value]
    return value


def _require_path_inside(path: Path, root: Path, label: str) -> Path:
    resolved = path.resolve()
    resolved_root = root.resolve()
    if resolved != resolved_root and resolved_root not in resolved.parents:
        raise ValueError(f"{label} escapes expected root: {resolved}")
    return resolved


def _extract_zip_safely(archive: zipfile.ZipFile, destination: Path) -> None:
    destination_root = destination.resolve()
    for member in archive.namelist():
        _validate_archive_member(member, destination_root)
        archive.extract(member, destination)


def _safe_tar_members(archive: tarfile.TarFile, destination: Path) -> list[tarfile.TarInfo]:
    destination_root = destination.resolve()
    safe_members = []
    for member in archive.getmembers():
        _validate_archive_member(member.name, destination_root)
        if not (member.isfile() or member.isdir()):
            raise ValueError(f"Unsafe path in archive: {member.name}")
        safe_members.append(member)
    return safe_members


def _validate_archive_member(name: str, destination_root: Path) -> None:
    normalized = posixpath.normpath(name)
    if normalized.startswith("../") or normalized == ".." or posixpath.isabs(normalized):
        raise ValueError(f"Unsafe path in archive: {name}")
    target = (destination_root / normalized).resolve()
    if target != destination_root and destination_root not in target.parents:
        raise ValueError(f"Unsafe path in archive: {name}")
