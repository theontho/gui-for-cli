#!/usr/bin/env python3
"""Install and launch the Android Compose app on a connected device or emulator."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "benchmarking"))
from android import adb_command, default_android_tool, ensure_device, run  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--package", default="dev.guiforcli.compose.android")
    parser.add_argument("--activity", default="dev.guiforcli.compose.android/.MainActivity")
    parser.add_argument("--adb", type=Path, default=default_android_tool("platform-tools/adb"))
    parser.add_argument("--emulator", type=Path, default=default_android_tool("emulator/emulator"))
    parser.add_argument("--avd")
    args = parser.parse_args()

    if not args.apk.is_file():
        parser.error(f"APK does not exist: {args.apk}")
    if not args.adb.is_file():
        parser.error(f"adb does not exist: {args.adb}")

    setup = ensure_device(args)
    args.device_serial = setup.get("deviceSerial")
    run(adb_command(args, "install", "-r", str(args.apk)), timeout=120)
    run(adb_command(args, "shell", "am", "start", "-n", args.activity), timeout=30)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
