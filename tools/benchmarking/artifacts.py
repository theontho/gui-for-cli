from __future__ import annotations

from pathlib import Path
from typing import Iterable


def artifact_metadata(paths: list[Path], *, app_bundle_suffixes: Iterable[str] = ()) -> list[dict]:
    app_bundle_suffixes = set(app_bundle_suffixes)
    artifacts = []
    for path in paths:
        absolute = absolute_path(path)
        size_bytes = path_size_bytes(absolute)
        artifacts.append(
            {
                "path": str(absolute),
                "kind": artifact_kind(absolute, app_bundle_suffixes=app_bundle_suffixes),
                "sizeBytes": size_bytes,
                "sizeMB": round(size_bytes / 1_000_000, 3),
            }
        )
    return artifacts


def artifact_size_mb(paths: list[Path]) -> float | None:
    if not paths:
        return None
    return round(sum(path_size_bytes(absolute_path(path)) for path in paths) / 1_000_000, 3)


def artifact_kind(path: Path, *, app_bundle_suffixes: set[str]) -> str:
    if path.is_symlink():
        return "symlink"
    if path.is_dir() and path.suffix in app_bundle_suffixes:
        return "app bundle"
    if path.is_dir():
        return "directory"
    return "file"


def path_size_bytes(path: Path) -> int:
    if path.is_symlink():
        return path.lstat().st_size
    if path.is_file():
        return path.stat().st_size
    total = 0
    for child in path.rglob("*"):
        if child.is_symlink():
            total += child.lstat().st_size
        elif child.is_file():
            total += child.stat().st_size
    return total


def absolute_path(path: Path) -> Path:
    expanded = path.expanduser()
    if expanded.is_absolute():
        return expanded
    return Path.cwd() / expanded
