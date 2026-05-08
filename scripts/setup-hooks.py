#!/usr/bin/env python3
"""Install pre-commit and pre-push git hooks for this repo."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def run(command: str, args: list[str]) -> tuple[int, str]:
    try:
        proc = subprocess.run(
            [command, *args],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError as exc:
        return 1, str(exc)
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


HOOKS: list[tuple[str, str]] = [
    (
        "pre-commit",
        """#!/bin/sh
set -eu
cd "$(git rev-parse --show-toplevel)"
python3 scripts/verify-dev.py
make lint
""",
    ),
    (
        "pre-push",
        """#!/bin/sh
set -eu
cd "$(git rev-parse --show-toplevel)"
python3 scripts/verify-dev.py
make test
make build-cli
""",
    ),
]


def main() -> int:
    status, output = run("git", ["rev-parse", "--show-toplevel"])
    if status != 0:
        print("Skipping hook install: not inside a Git repository.")
        return 0

    root = Path(output.strip())
    hooks_dir = root / ".git" / "hooks"
    hooks_dir.mkdir(parents=True, exist_ok=True)

    for name, body in HOOKS:
        path = hooks_dir / name
        path.write_text(body, encoding="utf-8")
        os.chmod(path, 0o755)

    print("Installed pre-commit and pre-push hooks.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
