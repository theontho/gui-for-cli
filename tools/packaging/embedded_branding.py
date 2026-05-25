from __future__ import annotations

import json
import os
import shutil
import sys
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

_parent = Path(__file__).resolve().parents[2]
if str(_parent) not in sys.path:
    sys.path.insert(0, str(_parent))
from tools.devconfig import get_path
from tools.packaging.git_filters import copy_git_filtered


DEFAULT_EMBEDDED_BUNDLE_PATH = "examples/WGSExtract"
DISTRIBUTION_SUFFIXES = (
    "Linux AppImage WebUI",
    "macOS WebUI",
    "Windows WebUI",
    "Ubuntu WebUI",
    "Fedora WebUI",
    "Linux WebUI",
    "Arch WebUI",
    "macOS",
    "WebUI",
)


def macos_swiftui_app_name(app_name: str | None) -> str | None:
    return app_name_without_distribution_suffix(app_name)


def tauri_webui_app_name(app_name: str | None, platform: str) -> str | None:
    base_name = app_name_without_distribution_suffix(app_name)
    if platform == "darwin":
        return app_name_with_distribution_suffix(base_name, "WebUI")
    return base_name


def app_name_with_distribution_suffix(app_name: str | None, suffix: str) -> str | None:
    if app_name is None:
        return None
    stripped = app_name.strip()
    if not stripped:
        return None
    if stripped.lower().endswith(f" {suffix.lower()}"):
        return stripped
    return f"{stripped} {suffix}"


def app_name_without_distribution_suffix(app_name: str | None) -> str | None:
    if app_name is None:
        return None
    stripped = app_name.strip()
    if not stripped:
        return None
    normalized = stripped.lower()
    for suffix in sorted(DISTRIBUTION_SUFFIXES, key=len, reverse=True):
        normalized_suffix = suffix.lower()
        if normalized.endswith(f" {normalized_suffix}"):
            base_name = stripped[: -(len(suffix) + 1)].strip()
            return base_name or stripped
    return stripped


@dataclass(frozen=True)
class EmbeddedBranding:
    bundle_path: Path | None
    app_name: str | None
    app_version: str | None

    @property
    def enabled(self) -> bool:
        return self.bundle_path is not None or self.app_name is not None

    @property
    def effective_app_name(self) -> str | None:
        if self.app_name:
            return self.app_name
        if self.bundle_path is not None:
            return self.bundle_path.name
        return None

    @property
    def effective_macos_swiftui_app_name(self) -> str | None:
        return macos_swiftui_app_name(self.effective_app_name)

    def effective_tauri_webui_app_name(self, platform: str) -> str | None:
        return tauri_webui_app_name(self.effective_app_name, platform)

    @property
    def effective_app_version(self) -> str | None:
        return self.app_version


def env_value(*names: str) -> str:
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return ""


def config_value(section: str, key: str) -> str:
    value = get_path(section, key, default="")
    return str(value) if value else ""


def load_embedded_branding(repo_root: Path) -> EmbeddedBranding:
    bundle_value = (
        env_value("EMBEDDED_BUNDLE_PATH", "PACKAGE_BUNDLE_PATH")
        or get_path("packaging", "embedded_bundle_path", default="")
        or DEFAULT_EMBEDDED_BUNDLE_PATH
    )
    bundle_path: Path | None = None
    if bundle_value:
        candidate = Path(bundle_value)
        bundle_path = candidate if candidate.is_absolute() else repo_root / candidate
        bundle_path = bundle_path.resolve()
        if not bundle_path.exists():
            raise FileNotFoundError(
                f"Embedded bundle path does not exist: {bundle_path}"
            )
        manifest_path = bundle_path / "manifest.json"
        if not manifest_path.exists():
            raise FileNotFoundError(
                f"Embedded bundle is missing manifest.json: {manifest_path}"
            )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    else:
        manifest = {}

    app_name = (
        env_value("PACKAGE_APP_NAME", "EMBEDDED_APP_NAME")
        or get_path("packaging", "app_name", default="")
        or None
    )
    app_version = (
        env_value("PACKAGE_APP_VERSION", "EMBEDDED_APP_VERSION")
        or get_path("packaging", "app_version", default="")
        or string_value(manifest.get("version"))
        or None
    )
    return EmbeddedBranding(
        bundle_path=bundle_path, app_name=app_name, app_version=app_version
    )


def repo_relative_path(repo_root: Path, target: Path) -> str:
    try:
        return str(target.relative_to(repo_root))
    except ValueError:
        return str(target)


def string_value(value: object) -> str:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return ""


@contextmanager
def apple_embedded_branding(repo_root: Path):
    branding = load_embedded_branding(repo_root)
    if not branding.enabled:
        yield branding
        return

    identity_path = repo_root / "tmp/app-identity.json"
    demo_bundle_link = (
        repo_root
        / "platform/apple/shared/Sources/GUIForCLICore/Resources/DemoBundles/EmbeddedBundle"
    )

    previous_identity = identity_path.read_bytes() if identity_path.exists() else None
    previous_demo_bundle_path: Path | None = None
    previous_demo_bundle_symlink_target: str | None = None
    if demo_bundle_link.exists() or demo_bundle_link.is_symlink():
        if demo_bundle_link.is_symlink():
            previous_demo_bundle_symlink_target = os.readlink(demo_bundle_link)
            demo_bundle_link.unlink()
        else:
            import uuid

            backup_path = (
                repo_root / "tmp" / f"embedded-bundle-backup-{uuid.uuid4().hex}"
            )
            if demo_bundle_link.is_dir():
                shutil.copytree(demo_bundle_link, backup_path, symlinks=False)
                previous_demo_bundle_path = backup_path
                shutil.rmtree(demo_bundle_link)
            elif demo_bundle_link.exists():
                backup_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(demo_bundle_link, backup_path)
                previous_demo_bundle_path = backup_path
                demo_bundle_link.unlink()

    try:
        identity_path.parent.mkdir(parents=True, exist_ok=True)
        identity = {}
        if branding.bundle_path is not None:
            identity["embeddedBundlePath"] = repo_relative_path(
                repo_root, branding.bundle_path
            )
        bundle_identifier_name = app_name_without_distribution_suffix(
            branding.effective_app_name
        )
        if bundle_identifier_name:
            identity["bundleIdentifierName"] = bundle_identifier_name
        effective_app_name = branding.effective_macos_swiftui_app_name
        if effective_app_name:
            identity["displayName"] = effective_app_name
            identity["productName"] = effective_app_name
        effective_app_version = branding.effective_app_version
        if effective_app_version:
            identity["marketingVersion"] = effective_app_version
            identity["buildVersion"] = effective_app_version
        sparkle_appcast_url = (
            env_value("SPARKLE_APPCAST_URL")
            or config_value("sparkle.updater", "appcast_url")
        )
        if sparkle_appcast_url:
            identity["sparkleAppcastURL"] = sparkle_appcast_url
        sparkle_public_ed_key = (
            env_value("SPARKLE_PUBLIC_ED_KEY")
            or config_value("sparkle.updater", "public_ed_key")
        )
        if sparkle_public_ed_key:
            identity["sparklePublicEDKey"] = sparkle_public_ed_key
        identity_path.write_text(
            json.dumps(identity, indent=2) + "\n", encoding="utf-8"
        )

        if branding.bundle_path is not None:
            wgs_extract_path = repo_root / "examples/WGSExtract"
            if branding.bundle_path.resolve() != wgs_extract_path.resolve():
                if not copy_git_filtered(
                    branding.bundle_path, demo_bundle_link, repo_root
                ):
                    shutil.copytree(
                        branding.bundle_path, demo_bundle_link, symlinks=False
                    )

        yield branding
    finally:
        if previous_identity is None:
            identity_path.unlink(missing_ok=True)
        else:
            identity_path.write_bytes(previous_identity)

        if demo_bundle_link.exists() or demo_bundle_link.is_symlink():
            if demo_bundle_link.is_dir() and not demo_bundle_link.is_symlink():
                shutil.rmtree(demo_bundle_link)
            else:
                demo_bundle_link.unlink()
        if previous_demo_bundle_symlink_target is not None:
            demo_bundle_link.symlink_to(previous_demo_bundle_symlink_target)
        elif previous_demo_bundle_path is not None:
            if previous_demo_bundle_path.is_dir():
                shutil.copytree(
                    previous_demo_bundle_path, demo_bundle_link, symlinks=False
                )
                shutil.rmtree(previous_demo_bundle_path, ignore_errors=True)
            else:
                shutil.copy2(previous_demo_bundle_path, demo_bundle_link)
                previous_demo_bundle_path.unlink(missing_ok=True)
