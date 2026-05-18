#!/usr/bin/env python3
"""Check repository development environment readiness."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CheckResult:
    label: str
    passed: bool
    detail: str = ""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quiet", action="store_true", help="Suppress passing check output.")
    parser.add_argument("--repo-root", default=".", help="Repository root to check.")
    args = parser.parse_args(argv)

    repo_root = Path(args.repo_root).resolve()
    print_line("Running precheck...", quiet=args.quiet)
    checks = [
        check_command("Swift toolchain", ["swift", "--version"], cwd=repo_root),
        check_command("Xcode build tools", ["xcodebuild", "-version"], cwd=repo_root),
        check_command("swift-format", ["swift", "format", "--version"], cwd=repo_root),
        check_repository_hooks(repo_root),
        check_config_directory(),
    ]
    for check in checks:
        prefix = "OK" if check.passed else "FAIL"
        detail = f" - {check.detail}" if check.detail else ""
        print_line(f"{prefix} {check.label}{detail}", quiet=args.quiet and check.passed)
    if all(check.passed for check in checks):
        print_line("Precheck passed.", quiet=args.quiet)
        return 0
    return 1


def check_command(label: str, command: list[str], *, cwd: Path) -> CheckResult:
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
    except OSError as error:
        return CheckResult(label, False, str(error))
    return CheckResult(label, result.returncode == 0, first_line(result.stdout))


def check_repository_hooks(repo_root: Path) -> CheckResult:
    if not (repo_root / ".git").exists():
        return CheckResult("Repository hooks", False, "not inside the repository; run from the repo root")
    script = repo_root / "scripts" / "setup-hooks.py"
    if not script.exists():
        return CheckResult("Repository hooks", False, "scripts/setup-hooks.py was not found")
    try:
        result = subprocess.run(
            [sys.executable, "scripts/setup-hooks.py", "--check"],
            cwd=repo_root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
    except OSError as error:
        return CheckResult("Repository hooks", False, str(error))
    return CheckResult("Repository hooks", result.returncode == 0, first_line(result.stdout))


def check_config_directory() -> CheckResult:
    config_dir = app_config_dir()
    if config_dir.exists():
        probe = config_dir / f".write-test-{uuid.uuid4()}"
        try:
            probe.write_bytes(b"")
            probe.unlink(missing_ok=True)
            return CheckResult("Config directory", True, str(config_dir))
        except OSError as error:
            probe.unlink(missing_ok=True)
            return CheckResult("Config directory", False, str(error))
    parent = nearest_existing_parent(config_dir)
    writable = os.access(parent, os.W_OK)
    return CheckResult("Config directory parent", writable, str(parent))


def nearest_existing_parent(path: Path) -> Path:
    candidate = path.parent
    while not candidate.exists():
        next_candidate = candidate.parent
        if next_candidate == candidate:
            return candidate
        candidate = next_candidate
    return candidate


def app_config_dir() -> Path:
    override = os.environ.get("GUI_FOR_CLI_CONFIG_DIR")
    if override:
        return Path(override).expanduser()
    return app_support_dir()


def app_support_dir() -> Path:
    override = os.environ.get("GUI_FOR_CLI_APP_SUPPORT_NAME")
    name = safe_path_component(override) if override else "gui-for-cli"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / name
    data_home = os.environ.get("XDG_DATA_HOME")
    return (Path(data_home).expanduser() if data_home else Path.home() / ".local" / "share") / name


def safe_path_component(value: str) -> str:
    sanitized = "".join(character if character.isalnum() or character in "-_." else "-" for character in value)
    trimmed = sanitized.strip(".-")
    return trimmed or "bundle"


def first_line(value: str) -> str:
    return value.splitlines()[0] if value.splitlines() else ""


def print_line(value: str, *, quiet: bool) -> None:
    if not quiet:
        print(value)


if __name__ == "__main__":
    raise SystemExit(main())
