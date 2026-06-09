from __future__ import annotations

import os
import re
import gzip
import hashlib
import tarfile
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from tools.json_comments import loads_json_with_comments
from .localization import StringTable, load_strings

SAFE_ID = re.compile(r"[^A-Za-z0-9_.-]+")


@dataclass(frozen=True)
class Bundle:
    repo_root: Path
    bundle_root: Path
    workspace_root: Path
    locale: str
    manifest: dict[str, Any]
    strings: StringTable

    @property
    def display_name(self) -> str:
        return self.strings.text(self.manifest.get("displayName", self.manifest.get("id", "Bundle")))

    @property
    def terminal_text_direction(self) -> str:
        return str(self.manifest.get("terminalTextDirection") or "ltr").lower()

    @property
    def rtl_layout(self) -> bool:
        return self.strings.is_rtl


def load_bundle(bundle_path: Path, repo_root: Path, locale: str) -> Bundle:
    bundle_root, manifest = load_manifest(bundle_path, repo_root)
    pages = []
    for page_ref in manifest.get("pages", []):
        if isinstance(page_ref, str):
            page_path = bundle_root / "pages" / page_ref
            pages.append(loads_json_with_comments(page_path.read_text(encoding="utf-8")))
        elif isinstance(page_ref, dict):
            pages.append(page_ref)
        else:
            raise ValueError(f"Unsupported page reference: {page_ref!r}")
    manifest = {**manifest, "pages": pages}
    strings = load_strings(bundle_root, locale)
    workspace_root = resolve_workspace_root(repo_root, manifest)
    workspace_root.mkdir(parents=True, exist_ok=True)
    return Bundle(repo_root=repo_root, bundle_root=bundle_root, workspace_root=workspace_root, locale=locale, manifest=manifest, strings=strings)


def load_manifest(bundle_path: Path, repo_root: Path | None = None) -> tuple[Path, dict[str, Any]]:
    path = bundle_path.resolve()
    if path.is_file() and path.name == "manifest.json":
        root = path.parent
        manifest_path = path
    elif path.is_dir():
        root = find_manifest_root(path)
        manifest_path = root / "manifest.json"
    elif path.is_file() and repo_root is not None:
        root = extract_archive(path, repo_root)
        manifest_path = root / "manifest.json"
    else:
        raise FileNotFoundError(f"Expected bundle directory, manifest.json, or supported archive, got {bundle_path}")
    if not manifest_path.is_file():
        raise FileNotFoundError(f"Missing manifest.json at {manifest_path}")
    manifest = loads_json_with_comments(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        raise ValueError("manifest.json must contain an object")
    return root, manifest


def find_manifest_root(root: Path) -> Path:
    if (root / "manifest.json").is_file():
        return root
    children = [child for child in root.iterdir() if child.is_dir() and (child / "manifest.json").is_file()]
    if len(children) == 1:
        return children[0]
    return root


def extract_archive(path: Path, repo_root: Path) -> Path:
    target = archive_extract_root(path, repo_root)
    if not (target / ".complete").is_file():
        target.mkdir(parents=True, exist_ok=True)
        if zipfile.is_zipfile(path):
            extract_zip(path, target)
        elif tarfile.is_tarfile(path):
            extract_tar(path, target)
        elif path.suffix == ".gz":
            with gzip.open(path, "rb") as source:
                (target / "manifest.json").write_bytes(source.read())
        else:
            raise FileNotFoundError(f"Unsupported bundle archive: {path}")
        (target / ".complete").write_text("ok\n", encoding="utf-8")
    return find_manifest_root(target)


def archive_extract_root(path: Path, repo_root: Path) -> Path:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()[:12]
    name = SAFE_ID.sub("-", path.name).strip(".-") or "bundle"
    return (repo_root / "tmp" / "textual-bundles" / f"{name}-{digest}").resolve()


def extract_zip(path: Path, target: Path) -> None:
    with zipfile.ZipFile(path) as archive:
        for member in archive.infolist():
            destination = safe_destination(target, member.filename)
            if member.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member) as source:
                destination.write_bytes(source.read())


def extract_tar(path: Path, target: Path) -> None:
    with tarfile.open(path) as archive:
        for member in archive.getmembers():
            destination = safe_destination(target, member.name)
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                destination.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as source:
                    if source is not None:
                        destination.write_bytes(source.read())


def safe_destination(root: Path, member_name: str) -> Path:
    destination = (root / member_name).resolve()
    if root.resolve() not in [destination, *destination.parents]:
        raise ValueError(f"Archive member escapes bundle root: {member_name}")
    return destination


def resolve_workspace_root(repo_root: Path, manifest: dict[str, Any]) -> Path:
    override = os.environ.get("GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT")
    bundle_id = str(manifest.get("id") or "bundle")
    safe = SAFE_ID.sub("-", bundle_id).strip(".-") or "bundle"
    root = Path(override).expanduser() if override else repo_root / "tmp" / "textual-workspaces"
    return (root / safe).resolve()
