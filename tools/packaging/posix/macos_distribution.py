from __future__ import annotations

import os
import shutil
import struct
import subprocess
import zlib
from pathlib import Path

from common import copy_path
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
    return select_detected_developer_id_identity(team_id, available_developer_id_identities())


def select_detected_developer_id_identity(team_id: str, identities: list[tuple[str, str]]) -> str:
    candidates = [name for _, name in identities]
    if team_id:
        team_candidates = [candidate for candidate in candidates if f"({team_id})" in candidate]
        if team_candidates:
            return team_candidates[0]
        raise RuntimeError(f"No Developer ID Application identity was found for Apple team {team_id}.")
    return candidates[0] if candidates else ""


def resolved_signing_identity() -> str:
    return select_signing_identity(
        team_id=distribution_team_id(),
        configured_identity=distribution_signing_identity(),
        identities=available_developer_id_identities(),
    )


def select_signing_identity(
    *,
    team_id: str,
    configured_identity: str,
    identities: list[tuple[str, str]],
) -> str:
    if configured_identity:
        for identity_hash, identity_name in identities:
            if configured_identity in {identity_hash, identity_name}:
                return configured_identity
        raise RuntimeError(
            f"Configured signing identity was not found in the keychain: {configured_identity}. "
            "Import a Developer ID Application .p12 or update APPLE_SIGNING_IDENTITY."
        )
    return select_detected_developer_id_identity(team_id, identities)


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
    copy_path(app_path, staged_app)
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
    copy_path(exported_app, staged_app)
    sign_app(staged_app, signing_identity)
    verify_codesign(staged_app)

    if should_notarize():
        notarize_app(staged_app)
        staple(staged_app)
        validate_staple(staged_app)

    dmg_path = output_dir / distribution_dmg_name(app_name, app_version)
    create_dmg(staged_app, dmg_path, app_name)
    sign_dmg(dmg_path, signing_identity)
    if should_notarize():
        notarize(dmg_path)
        staple(dmg_path)
        validate_staple(dmg_path)
    return [staged_app, dmg_path]


def distribution_dmg_name(app_name: str, app_version: str | None) -> str:
    if not app_version:
        return f"{app_name}.dmg"
    safe_version = "".join(
        character if character.isalnum() or character in "._-" else "-"
        for character in app_version
    ).strip("-")
    if not safe_version:
        return f"{app_name}.dmg"
    return f"{app_name}-{safe_version}.dmg"


def dmg_background_enabled() -> bool:
    env_setting = env_value("PACKAGE_DMG_BACKGROUND", "DMG_BACKGROUND")
    if env_setting:
        return parse_bool_setting(env_setting, "PACKAGE_DMG_BACKGROUND")
    config_setting = get_path("packaging", "dmg_background", default=False)
    return parse_bool_setting(config_setting, "packaging.dmg_background")


def parse_bool_setting(value: object, name: str) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"", "0", "false", "no", "off"}:
            return False
    raise ValueError(f"{name} must be a boolean value: true/false, 1/0, yes/no, or on/off")


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
    configure_background = dmg_background_enabled()
    if configure_background:
        background_dir = staging_dir / ".background"
        background_dir.mkdir(parents=True, exist_ok=True)
        write_dmg_background(background_dir / "installer.png", app_path.stem)
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
            "-fs",
            "HFS+",
            str(temp_rw_dmg),
        ],
        check=True,
    )
    try:
        if configure_background:
            mount_root.mkdir(parents=True, exist_ok=True)
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
                subprocess.run(["hdiutil", "detach", str(mount_root)], check=False)
        subprocess.run(
            ["hdiutil", "convert", str(temp_rw_dmg), "-ov", "-format", "UDZO", "-o", str(dmg_path)],
            check=True,
        )
    finally:
        shutil.rmtree(staging_dir, ignore_errors=True)
        shutil.rmtree(mount_root, ignore_errors=True)
        temp_rw_dmg.unlink(missing_ok=True)


FONT_5X7: dict[str, tuple[str, ...]] = {
    " ": ("00000", "00000", "00000", "00000", "00000", "00000", "00000"),
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "C": ("01111", "10000", "10000", "10000", "10000", "10000", "01111"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "G": ("01111", "10000", "10000", "10011", "10001", "10001", "01111"),
    "I": ("11111", "00100", "00100", "00100", "00100", "00100", "11111"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "10101", "01010"),
    "X": ("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
}


def write_dmg_background(path: Path, app_name: str) -> None:
    width = 640
    height = 380
    background = (246, 248, 252)
    accent = (45, 105, 210)
    muted = (95, 105, 120)
    pixels = bytearray(background * width * height)

    def set_pixel(x: int, y: int, color: tuple[int, int, int]) -> None:
        if 0 <= x < width and 0 <= y < height:
            offset = (y * width + x) * 3
            pixels[offset : offset + 3] = bytes(color)

    def fill_rect(x: int, y: int, rect_width: int, rect_height: int, color: tuple[int, int, int]) -> None:
        for yy in range(y, y + rect_height):
            for xx in range(x, x + rect_width):
                set_pixel(xx, yy, color)

    def draw_text(text: str, x: int, y: int, scale: int, color: tuple[int, int, int]) -> None:
        cursor = x
        for character in text.upper():
            glyph = FONT_5X7.get(character, FONT_5X7[" "])
            for row_index, row in enumerate(glyph):
                for column_index, bit in enumerate(row):
                    if bit == "1":
                        fill_rect(
                            cursor + column_index * scale,
                            y + row_index * scale,
                            scale,
                            scale,
                            color,
                        )
            cursor += 6 * scale

    def draw_arrow() -> None:
        shaft_y = 186
        fill_rect(240, shaft_y, 150, 10, accent)
        for delta in range(52):
            fill_rect(390 + delta, shaft_y - delta, 4, 10 + delta * 2, accent)

    draw_arrow()
    draw_text(f"DRAG {app_name}", 56, 54, 4, muted)
    draw_text("TO APPLICATIONS", 146, 306, 4, muted)
    write_png(path, width, height, bytes(pixels))


def write_png(path: Path, width: int, height: int, rgb: bytes) -> None:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    rows = b"".join(
        b"\x00" + rgb[row * width * 3 : (row + 1) * width * 3] for row in range(height)
    )
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows, level=9))
        + chunk(b"IEND", b"")
    )


def configure_dmg_window(mount_root: Path, volume_name: str, app_name: str) -> None:
    background_path = mount_root / ".background/installer.png"
    script = f'''
      tell application "Finder"
        set dmgFolder to POSIX file "{mount_root}" as alias
        open dmgFolder
        delay 1
        set dmgWindow to container window of dmgFolder
        set current view of dmgWindow to icon view
        try
          set toolbar visible of dmgWindow to false
        end try
        try
          set statusbar visible of dmgWindow to false
        end try
        set bounds of dmgWindow to {{120, 120, 760, 500}}
        set viewOptions to icon view options of dmgWindow
        try
          set arrangement of viewOptions to not arranged
        end try
        set icon size of viewOptions to 144
        set text size of viewOptions to 16
        set background picture of viewOptions to POSIX file "{background_path}"
        set position of item "{app_name}" of dmgFolder to {{160, 210}}
        set position of item "Applications" of dmgFolder to {{480, 210}}
        update dmgFolder without registering applications
        delay 2
        close dmgWindow
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


def notarize_app(path: Path) -> None:
    archive = path.with_suffix(".notary.zip")
    archive.unlink(missing_ok=True)
    try:
        subprocess.run(
            ["ditto", "-c", "-k", "--keepParent", path.name, archive.name],
            cwd=path.parent,
            check=True,
        )
        notarize(archive)
    finally:
        archive.unlink(missing_ok=True)


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
        raise RuntimeError(
            "notarytool_auth_args refuses to pass app-specific passwords on the command line. "
            "Run `xcrun notarytool store-credentials` and set APPLE_NOTARY_PROFILE or "
            "apple.signing.notary_profile instead."
        )

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
