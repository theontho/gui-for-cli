#!/usr/bin/env python3
"""Run the staged Electron app for the current host platform."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("out/dev/electron")
    executable = find_executable(out_dir)
    subprocess.run([str(executable)], check=True, env=os.environ.copy())
    return 0


def find_executable(out_dir: Path) -> Path:
    if sys.platform == "darwin":
        pattern = "**/*.app/Contents/MacOS/GUI for CLI Electron"
    elif sys.platform.startswith("win"):
        pattern = "**/GUI for CLI Electron.exe"
    else:
        pattern = "**/GUI for CLI Electron"

    candidates = sorted(path for path in out_dir.glob(pattern) if path.is_file())
    if not candidates:
        raise FileNotFoundError(f"Electron executable not found under {out_dir}")
    if len(candidates) > 1:
        found = ", ".join(str(path) for path in candidates)
        raise RuntimeError(
            f"Multiple Electron executables found under {out_dir}; "
            f"pass a narrower output directory or keep a single artifact: {found}"
        )
    return candidates[0]


if __name__ == "__main__":
    raise SystemExit(main())
