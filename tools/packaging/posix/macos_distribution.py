from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from tools.devconfig import get_path


def env_value(*names: str) -> str:
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return ""


def config_value(*path: str) -> str:
    value = get_path(*path, default="")
    return value if isinstance(value, str) else ""



def distribution_team_id() -> str:
    return (
        env_value("APPLE_DEVELOPMENT_TEAM", "APPLE_TEAM_ID")
        or config_value("apple", "signing", "development_team")
        or config_value("apple", "signing", "team_id")
    )


def distribution_signing_identity() -> str:
    return env_value("APPLE_SIGNING_IDENTITY") or config_value("apple", "signing", "signing_identity")


def available_developer_id_identities() -> list[tuple[str, str]]:
    result = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return []
    identities: list[tuple[str, str]] = []
    for line in result.stdout.splitlines():
        marker = '"Developer ID Application:'
        if marker not in line:
            continue
        parts = line.split()
        identity_hash = parts[1] if len(parts) > 1 else ""
        try:
            name = line.split('"', 2)[1]
        except IndexError:
            continue
        identities.append((identity_hash, name))
    return identities


def detected_developer_id_identity(team_id: str) -> str:
    candidates = [name for _, name in available_developer_id_identities()]
    if team_id:
        team_candidates = [candidate for candidate in candidates if f"({team_id})" in candidate]
        if team_candidates:
            return team_candidates[0]
    return candidates[0] if candidates else ""


def resolved_signing_identity() -> str:
    team_id = distribution_team_id()
    configured_identity = distribution_signing_identity()
    identities = available_developer_id_identities()
    if configured_identity:
        for identity_hash, identity_name in identities:
            if configured_identity in {identity_hash, identity_name}:
                return configured_identity
        raise RuntimeError(
            f"Configured signing identity was not found in the keychain: {configured_identity}. "
            "Import a Developer ID Application .p12 or update APPLE_SIGNING_IDENTITY."
        )
    return detected_developer_id_identity(team_id)


def should_sign() -> bool:
    return bool(distribution_team_id() or distribution_signing_identity())


def should_notarize() -> bool:
    return bool(notarytool_auth_args())


def build_swift_distribution(
    *,
    repo_root: Path,
    workspace: Path,
    scheme: str,
    derived_data_path: Path,
    destination: str,
    app_name: str,
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
            output_dir=output_dir,
        )
    return unsigned_swift_distribution(
        repo_root=repo_root,
        workspace=workspace,
        scheme=scheme,
        derived_data_path=derived_data_path,
        destination=destination,
        app_name=app_name,
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
    copy_path(app_path, staged_app)
    dmg_path = output_dir / f"{app_name}.dmg"
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
    copy_path(exported_app, staged_app)
    sign_app(staged_app, signing_identity)
    verify_codesign(staged_app)

    dmg_path = output_dir / f"{app_name}.dmg"
    create_dmg(staged_app, dmg_path, app_name)
    sign_dmg(dmg_path, signing_identity)
    if should_notarize():
        notarize(dmg_path)
        staple(dmg_path)
        staple(staged_app)
        validate_staple(dmg_path)
        validate_staple(staged_app)
    return [staged_app, dmg_path]


def copy_path(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if shutil.which("ditto"):
        if dest.exists() and dest.is_dir():
            shutil.rmtree(dest)
        subprocess.run(["ditto", str(src), str(dest)], check=True)
        return
    if src.is_dir():
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(src, dest, symlinks=True)
    else:
        shutil.copy2(src, dest)


def create_dmg(app_path: Path, dmg_path: Path, volume_name: str) -> None:
    staging_dir = dmg_path.parent / f"{app_path.stem}-dmg"
    temp_rw_dmg = dmg_path.with_suffix(".tmp.dmg")
    mount_root = dmg_path.parent / f".{app_path.stem}-mount"
    for path in (staging_dir, mount_root):
        if path.exists():
            shutil.rmtree(path)
    staging_dir.mkdir(parents=True, exist_ok=True)
    copy_path(app_path, staging_dir / app_path.name)
    (staging_dir / "Applications").symlink_to("/Applications")
    dmg_path.unlink(missing_ok=True)
    temp_rw_dmg.unlink(missing_ok=True)
    subprocess.run(
        [
            "hdiutil",
            "create",
            "-volname",
            volume_name,
            "-srcfolder",
            str(staging_dir),
            "-ov",
            "-format",
            "UDRW",
            str(temp_rw_dmg),
        ],
        check=True,
    )
    mount_root.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            [
                "hdiutil",
                "attach",
                "-nobrowse",
                "-mountpoint",
                str(mount_root),
                str(temp_rw_dmg),
            ],
            check=True,
        )
        try:
            configure_dmg_window(mount_root, volume_name, app_path.name)
        finally:
            subprocess.run(["hdiutil", "detach", str(mount_root)], check=True)
        subprocess.run(
            ["hdiutil", "convert", str(temp_rw_dmg), "-ov", "-format", "UDZO", "-o", str(dmg_path)],
            check=True,
        )
    finally:
        shutil.rmtree(staging_dir, ignore_errors=True)
        shutil.rmtree(mount_root, ignore_errors=True)
        temp_rw_dmg.unlink(missing_ok=True)


def configure_dmg_window(mount_root: Path, volume_name: str, app_name: str) -> None:
    script = f'''
      tell application "Finder"
        tell disk "{volume_name}"
          open
          set current view of container window to icon view
          set toolbar visible of container window to false
          set statusbar visible of container window to false
          set the bounds of container window to {{120, 120, 760, 520}}
          set viewOptions to the icon view options of container window
          set arrangement of viewOptions to not arranged
          set icon size of viewOptions to 144
          set text size of viewOptions to 16
          update without registering applications
          delay 1
          close
        end tell
      end tell
    '''
    subprocess.run(["osascript", "-e", script], check=False)



def verify_codesign(path: Path) -> None:
    subprocess.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(path)], check=True)


def sign_app(path: Path, signing_identity: str) -> None:
    subprocess.run(
        [
            "codesign",
            "--force",
            "--deep",
            "--sign",
            signing_identity,
            "--options",
            "runtime",
            "--timestamp",
            str(path),
        ],
        check=True,
    )


def sign_dmg(path: Path, signing_identity: str) -> None:
    subprocess.run(["codesign", "--force", "--sign", signing_identity, "--timestamp", str(path)], check=True)
    subprocess.run(["codesign", "--verify", "--verbose=2", str(path)], check=True)


def notarytool_auth_args() -> list[str]:
    profile = env_value("APPLE_NOTARY_PROFILE") or config_value("apple", "signing", "notary_profile")
    if profile:
        return ["--keychain-profile", profile]

    api_key_path = env_value("APPLE_API_KEY_PATH")
    api_key_id = env_value("APPLE_API_KEY_ID")
    api_issuer = env_value("APPLE_API_ISSUER")
    if api_key_path and api_key_id and api_issuer:
        return ["--key", api_key_path, "--key-id", api_key_id, "--issuer", api_issuer]

    apple_id = env_value("APPLE_ID") or config_value("apple", "signing", "apple_id")
    password = env_value("APPLE_APP_SPECIFIC_PASSWORD", "APPLE_PASSWORD") or config_value(
        "apple", "signing", "app_specific_password"
    )
    team_id = (
        env_value("APPLE_TEAM_ID", "APPLE_DEVELOPMENT_TEAM")
        or config_value("apple", "signing", "team_id")
        or config_value("apple", "signing", "development_team")
    )
    if apple_id and password and team_id:
        return ["--apple-id", apple_id, "--password", password, "--team-id", team_id]

    return []


def notarize(path: Path) -> None:
    auth_args = notarytool_auth_args()
    if not auth_args:
        return
    subprocess.run(["xcrun", "notarytool", "submit", str(path), "--wait", *auth_args], check=True)


def staple(path: Path) -> None:
    subprocess.run(["xcrun", "stapler", "staple", "-v", str(path)], check=True)


def validate_staple(path: Path) -> None:
    subprocess.run(["xcrun", "stapler", "validate", "-v", str(path)], check=True)
