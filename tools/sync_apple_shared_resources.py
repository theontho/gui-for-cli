#!/usr/bin/env python3
from __future__ import annotations

import fcntl
import shutil
import sys
from contextlib import contextmanager
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.packaging.embedded_branding import load_embedded_branding
from tools.packaging.git_filters import copy_git_filtered

RESOURCE_ROOT = REPO_ROOT / "platform/apple/shared/Sources/GUIForCLICore/Resources"
LOCK_PATH = REPO_ROOT / "tmp/apple-shared-resources.lock"


def replace_tree(src: Path, dest: Path) -> None:
    if not src.exists():
        raise FileNotFoundError(f"Missing source resource tree: {src}")
    if dest.exists() or dest.is_symlink():
        if dest.is_dir() and not dest.is_symlink():
            shutil.rmtree(dest, ignore_errors=True)
        else:
            dest.unlink(missing_ok=True)
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not copy_git_filtered(src, dest, REPO_ROOT):
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

        # Load embedded branding to determine if we should package WGSExtract
        branding = load_embedded_branding(REPO_ROOT)

        # Clear out existing WGSExtract and EmbeddedBundle directories in resources
        wgs_dest = RESOURCE_ROOT / "DemoBundles/WGSExtract"
        embed_dest = RESOURCE_ROOT / "DemoBundles/EmbeddedBundle"

        for d in (wgs_dest, embed_dest):
            if d.exists() or d.is_symlink():
                if d.is_dir() and not d.is_symlink():
                    shutil.rmtree(d, ignore_errors=True)
                else:
                    d.unlink(missing_ok=True)

        # Construct sync targets dynamically
        sync_targets = [
            (REPO_ROOT / "resources/BuiltinStrings", RESOURCE_ROOT / "BuiltinStrings"),
            (REPO_ROOT / "resources/BuiltinIconMap", RESOURCE_ROOT / "BuiltinIconMap"),
        ]

        is_custom_bundle = False
        if branding.bundle_path is not None:
            wgs_extract_path = REPO_ROOT / "examples/WGSExtract"
            if branding.bundle_path.resolve() != wgs_extract_path.resolve():
                is_custom_bundle = True

        if not is_custom_bundle:
            # If default/no custom branding, sync WGSExtract
            sync_targets.append((REPO_ROOT / "examples/WGSExtract", wgs_dest))

        for src, dest in sync_targets:
            replace_tree(src, dest)

        for ds_store in RESOURCE_ROOT.rglob(".DS_Store"):
            ds_store.unlink()

    print(f"Synced Apple shared resources into {RESOURCE_ROOT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
