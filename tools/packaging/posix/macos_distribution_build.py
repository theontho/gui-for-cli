from __future__ import annotations

import subprocess
from pathlib import Path

from common import copy_path

try:
    from .macos_distribution_config import distribution_team_id, require_notarization, resolved_signing_identity, should_notarize, should_sign
    from .macos_distribution_dmg import create_dmg, distribution_dmg_name
    from .macos_distribution_signing import (
        ad_hoc_sign_app,
        assess_spctl,
        notarize,
        notarize_app,
        sign_app,
        sign_dmg,
        staple,
        validate_staple,
        verify_codesign,
    )
except ImportError:  # pragma: no cover - script execution path
    from macos_distribution_config import distribution_team_id, require_notarization, resolved_signing_identity, should_notarize, should_sign
    from macos_distribution_dmg import create_dmg, distribution_dmg_name
    from macos_distribution_signing import (
        ad_hoc_sign_app,
        assess_spctl,
        notarize,
        notarize_app,
        sign_app,
        sign_dmg,
        staple,
        validate_staple,
        verify_codesign,
    )


def build_swift_distribution(
    *,
    repo_root: Path,
    workspace: Path,
    scheme: str,
    derived_data_path: Path,
    destination: str,
    app_name: str,
    app_version: str | None,
    output_dir: Path,
) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    if should_sign():
        return signed_swift_distribution(
            repo_root=repo_root,
            workspace=workspace,
            scheme=scheme,
            derived_data_path=derived_data_path,
            destination=destination,
            app_name=app_name,
            app_version=app_version,
            output_dir=output_dir,
        )
    return unsigned_swift_distribution(
        repo_root=repo_root,
        workspace=workspace,
        scheme=scheme,
        derived_data_path=derived_data_path,
        destination=destination,
        app_name=app_name,
        app_version=app_version,
        output_dir=output_dir,
    )


def unsigned_swift_distribution(
    *,
    repo_root: Path,
    workspace: Path,
    scheme: str,
    derived_data_path: Path,
    destination: str,
    app_name: str,
    app_version: str | None,
    output_dir: Path,
) -> list[Path]:
    subprocess.run(
        [
            "xcodebuild",
            "-workspace",
            str(workspace),
            "-scheme",
            scheme,
            "-configuration",
            "Release",
            "-derivedDataPath",
            str(derived_data_path),
            "-destination",
            destination,
            "build",
            "CODE_SIGNING_ALLOWED=NO",
        ],
        cwd=repo_root,
        check=True,
    )
    app_path = derived_data_path / "Build/Products/Release" / f"{app_name}.app"
    staged_app = output_dir / f"{app_name}.app"
    copy_path(app_path, staged_app, git_filtered=False)
    ad_hoc_sign_app(staged_app)
    verify_codesign(staged_app)
    dmg_path = output_dir / distribution_dmg_name(app_name, app_version)
    create_dmg(staged_app, dmg_path, app_name)
    return [staged_app, dmg_path]


def signed_swift_distribution(
    *,
    repo_root: Path,
    workspace: Path,
    scheme: str,
    derived_data_path: Path,
    destination: str,
    app_name: str,
    app_version: str | None,
    output_dir: Path,
) -> list[Path]:
    team_id = distribution_team_id()
    signing_identity = resolved_signing_identity()
    if not signing_identity:
        raise RuntimeError(
            "Signed SwiftUI packaging requires a valid Developer ID Application identity. "
            "Set APPLE_SIGNING_IDENTITY or import APPLE_CERTIFICATE_P12 into the keychain."
        )

    subprocess.run(
        [
            "xcodebuild",
            "-workspace",
            str(workspace),
            "-scheme",
            scheme,
            "-configuration",
            "Release",
            "-derivedDataPath",
            str(derived_data_path),
            "-destination",
            destination,
            "build",
            "CODE_SIGNING_ALLOWED=NO",
            *([f"DEVELOPMENT_TEAM={team_id}"] if team_id else []),
        ],
        cwd=repo_root,
        check=True,
    )

    exported_app = derived_data_path / "Build/Products/Release" / f"{app_name}.app"
    staged_app = output_dir / f"{app_name}.app"
    copy_path(exported_app, staged_app, git_filtered=False)
    sign_app(staged_app, signing_identity)
    verify_codesign(staged_app)

    notarization_required = require_notarization()
    notarize_distribution = should_notarize()
    if notarization_required and not notarize_distribution:
        raise RuntimeError(
            "Signed SwiftUI packaging requires notarization credentials when "
            "PACKAGE_REQUIRE_NOTARIZATION=1. Configure APPLE_NOTARY_PROFILE or "
            "APPLE_API_KEY_PATH/APPLE_API_KEY_ID/APPLE_API_ISSUER."
        )

    if notarize_distribution:
        notarize_app(staged_app)
        staple(staged_app)
        validate_staple(staged_app)
        assess_spctl(staged_app, "exec")

    dmg_path = output_dir / distribution_dmg_name(app_name, app_version)
    create_dmg(staged_app, dmg_path, app_name)
    sign_dmg(dmg_path, signing_identity)
    if notarize_distribution:
        notarize(dmg_path)
        staple(dmg_path)
        validate_staple(dmg_path)
        assess_spctl(dmg_path, "install")
    return [staged_app, dmg_path]
