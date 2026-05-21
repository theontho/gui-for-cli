#!/usr/bin/env python3
from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.packaging.embedded_branding import load_embedded_branding
from tools.packaging.git_filters import copy_git_filtered

RESOURCE_BUNDLE_NAME = "GUIForCLIShared_GUIForCLICore.bundle"


def app_path_from_env() -> Path:
    target_build_dir = os.environ.get("TARGET_BUILD_DIR")
    wrapper_name = os.environ.get("WRAPPER_NAME")
    if not target_build_dir or not wrapper_name:
        raise RuntimeError("TARGET_BUILD_DIR and WRAPPER_NAME are required")
    return Path(target_build_dir) / wrapper_name


def bundle_resource_root(bundle_path: Path) -> Path:
    macos_root = bundle_path / "Contents/Resources/Resources"
    if macos_root.exists() or (bundle_path / "Contents/Resources").exists():
        return macos_root
    return bundle_path / "Resources"


def copy_tree(src: Path, dest: Path) -> None:
    if dest.exists() or dest.is_symlink():
        if dest.is_dir() and not dest.is_symlink():
            shutil.rmtree(dest, ignore_errors=True)
        else:
            dest.unlink(missing_ok=True)
    temp_dest = dest.parent / f".{dest.name}.tmp-sync"
    if temp_dest.exists() or temp_dest.is_symlink():
        if temp_dest.is_dir() and not temp_dest.is_symlink():
            shutil.rmtree(temp_dest, ignore_errors=True)
        else:
            temp_dest.unlink(missing_ok=True)
    temp_dest.parent.mkdir(parents=True, exist_ok=True)
    if not copy_git_filtered(src, temp_dest, REPO_ROOT):
        shutil.copytree(src, temp_dest, symlinks=False)
    shutil.move(str(temp_dest), str(dest))


def sync_into(bundle_path: Path) -> None:
    resource_root = bundle_resource_root(bundle_path)
    resource_root.mkdir(parents=True, exist_ok=True)

    # Load branding to dynamically construct build resources
    branding = load_embedded_branding(REPO_ROOT)
    wgs_extract_path = REPO_ROOT / "examples/WGSExtract"

    is_custom_bundle = False
    if (
        branding.bundle_path is not None
        and branding.bundle_path.resolve() != wgs_extract_path.resolve()
    ):
        is_custom_bundle = True

    # Clear existing locations in build resources to avoid stale resources
    wgs_dest = resource_root / "DemoBundles/WGSExtract"
    embed_dest = resource_root / "DemoBundles/EmbeddedBundle"

    for d in (wgs_dest, embed_dest):
        if d.exists() or d.is_symlink():
            if d.is_dir() and not d.is_symlink():
                shutil.rmtree(d, ignore_errors=True)
            else:
                d.unlink(missing_ok=True)

    sources = [
        (REPO_ROOT / "resources/BuiltinStrings", Path("BuiltinStrings")),
        (REPO_ROOT / "resources/BuiltinIconMap", Path("BuiltinIconMap")),
    ]

    if is_custom_bundle:
        # Copy custom embedded bundle
        src = (
            REPO_ROOT
            / "platform/apple/shared/Sources/GUIForCLICore/Resources/DemoBundles/EmbeddedBundle"
        )
        if src.exists():
            sources.append((src, Path("DemoBundles/EmbeddedBundle")))
    else:
        # Copy default WGSExtract
        sources.append((wgs_extract_path, Path("DemoBundles/WGSExtract")))

    for src, relative_dest in sources:
        if src.exists():
            copy_tree(src, resource_root / relative_dest)

    for ds_store in resource_root.rglob(".DS_Store"):
        ds_store.unlink()


def main() -> int:
    app_path = app_path_from_env()
    bundles = sorted(app_path.rglob(RESOURCE_BUNDLE_NAME))
    if not bundles:
        raise FileNotFoundError(
            f"Could not find {RESOURCE_BUNDLE_NAME} under {app_path}"
        )
    for bundle_path in bundles:
        sync_into(bundle_path)
        print(f"Synced built Apple resources into {bundle_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
