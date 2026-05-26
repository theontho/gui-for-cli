from __future__ import annotations

import os
import shutil
import struct
import subprocess
import zlib
from pathlib import Path

from common import copy_path

try:
    from .macos_distribution_config import parse_bool_setting
except ImportError:  # pragma: no cover - script execution path
    from macos_distribution_config import parse_bool_setting
from tools.devconfig import get_path


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
    for env_name in ("PACKAGE_DMG_BACKGROUND", "DMG_BACKGROUND"):
        env_setting = os.environ.get(env_name)
        if env_setting:
            return parse_bool_setting(env_setting, env_name)
    config_setting = get_path("packaging", "dmg_background", default=False)
    return parse_bool_setting(config_setting, "packaging.dmg_background")


def create_dmg(app_path: Path, dmg_path: Path, volume_name: str) -> None:
    staging_dir = dmg_path.parent / f"{app_path.stem}-dmg"
    temp_rw_dmg = dmg_path.with_suffix(".tmp.dmg")
    mount_root = dmg_path.parent / f".{app_path.stem}-mount"
    for path in (staging_dir, mount_root):
        if path.exists():
            shutil.rmtree(path)
    staging_dir.mkdir(parents=True, exist_ok=True)
    copy_path(app_path, staging_dir / app_path.name, git_filtered=False)
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
