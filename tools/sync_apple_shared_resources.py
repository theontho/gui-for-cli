#!/usr/bin/env python3
from __future__ import annotations

import fcntl
import shutil
from contextlib import contextmanager
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
RESOURCE_ROOT = REPO_ROOT / "platform/apple/shared/Sources/GUIForCLICore/Resources"
LOCK_PATH = REPO_ROOT / "tmp/apple-shared-resources.lock"
SYNC_TARGETS = (
    (REPO_ROOT / "resources/BuiltinStrings", RESOURCE_ROOT / "BuiltinStrings"),
    (REPO_ROOT / "resources/BuiltinIconMap", RESOURCE_ROOT / "BuiltinIconMap"),
    (REPO_ROOT / "examples/WGSExtract", RESOURCE_ROOT / "DemoBundles/WGSExtract"),
)


def replace_tree(src: Path, dest: Path) -> None:
    if not src.exists():
        raise FileNotFoundError(f"Missing source resource tree: {src}")
    if dest.exists() or dest.is_symlink():
        if dest.is_dir() and not dest.is_symlink():
            shutil.rmtree(dest, ignore_errors=True)
        else:
            dest.unlink(missing_ok=True)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dest, symlinks=False)



@contextmanager
def sync_lock():
    LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOCK_PATH.open("w") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)



def main() -> int:
    with sync_lock():
        RESOURCE_ROOT.mkdir(parents=True, exist_ok=True)
        for src, dest in SYNC_TARGETS:
            replace_tree(src, dest)
        for ds_store in RESOURCE_ROOT.rglob('.DS_Store'):
            ds_store.unlink()
    print(f"Synced Apple shared resources into {RESOURCE_ROOT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
