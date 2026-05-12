#!/usr/bin/env python3
"""Run the same checks GitHub Actions runs in CI, locally.

Usage:
  python3 scripts/ci-local.py            # run all CI steps
  python3 scripts/ci-local.py --fast     # skip iOS build (slowest step)
  python3 scripts/ci-local.py --list     # list steps without running

Exit code mirrors the first failing step.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


@dataclass
class Step:
    name: str
    command: list[str]
    fast_skip: bool = False  # skipped in --fast mode
    optional: bool = False  # missing tools yield warning, not failure


def steps(skip_tuist_install: bool) -> list[Step]:
    out: list[Step] = [
        Step("swift package resolve", ["swift", "package", "resolve"]),
        Step(
            "swift format lint",
            [
                "swift",
                "format",
                "lint",
                "--recursive",
                "Sources",
                "Tests",
                "Apps",
                "scripts",
                "Project.swift",
                "Tuist.swift",
            ],
        ),
        Step("lint locales", ["python3", "scripts/lint-locales.py", "--strict"]),
        Step(
            "validate example bundles",
            ["swift", "run", "gui-for-cli", "bundle", "validate", "--strict", "Examples/WGSExtract"],
        ),
        Step("swift test", ["swift", "test", "--parallel"]),
        Step("build CLI release", ["swift", "build", "-c", "release"]),
        Step("CLI smoke test", ["swift", "run", "gui-for-cli", "--version"]),
        Step("slint test", ["cargo", "test", "--manifest-path", "Apps/Slint/Cargo.toml"]),
        Step("raygui test", ["cargo", "test", "--manifest-path", "Apps/Raygui/Cargo.toml"]),
        Step(
            "raygui bundle smoke",
            [
                "cargo",
                "run",
                "--manifest-path",
                "Apps/Raygui/Cargo.toml",
                "--release",
                "--",
                "--check",
            ],
        ),
        Step(
            "slint benchmark smoke",
            [
                "cargo",
                "run",
                "--manifest-path",
                "Apps/Slint/Cargo.toml",
                "--release",
                "--",
                "--benchmark",
                "--once",
            ],
        ),
    ]
    if not skip_tuist_install:
        out.append(Step("tuist install", ["./scripts/tuist.sh", "install"]))
    out += [
        Step("tuist generate", ["./scripts/tuist.sh", "generate", "--no-open"]),
        Step(
            "build iOS app",
            [
                "xcodebuild",
                "-workspace",
                "GUIForCLI.xcworkspace",
                "-scheme",
                "GUIForCLIiOS",
                "-destination",
                "generic/platform=iOS Simulator",
                "build",
                "CODE_SIGNING_ALLOWED=NO",
            ],
            fast_skip=True,
        ),
        Step(
            "build macOS app",
            [
                "xcodebuild",
                "-workspace",
                "GUIForCLI.xcworkspace",
                "-scheme",
                "GUIForCLIMac",
                "build",
                "CODE_SIGNING_ALLOWED=NO",
            ],
        ),
    ]
    return out


def run_step(step: Step, env: dict[str, str]) -> tuple[bool, float]:
    print(f"\n\033[1;36m▶ {step.name}\033[0m")
    print(f"  $ {' '.join(step.command)}")
    start = time.monotonic()
    try:
        proc = subprocess.run(step.command, cwd=REPO_ROOT, env=env, check=False)
    except FileNotFoundError as exc:
        elapsed = time.monotonic() - start
        print(f"\033[1;31m  missing tool: {exc}\033[0m")
        return False, elapsed
    elapsed = time.monotonic() - start
    if proc.returncode != 0:
        print(f"\033[1;31m  ✗ failed ({elapsed:.1f}s)\033[0m")
        return False, elapsed
    print(f"\033[1;32m  ✓ ok ({elapsed:.1f}s)\033[0m")
    return True, elapsed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fast", action="store_true", help="Skip slow steps (iOS build)."
    )
    parser.add_argument(
        "--list", action="store_true", help="Print step list and exit."
    )
    parser.add_argument(
        "--skip-tuist-install",
        action="store_true",
        help="Skip 'tuist install' (use if previously cached).",
    )
    args = parser.parse_args()

    env = os.environ.copy()
    # Strip env vars that break SPM resolution under xcodebuild on macOS.
    for key in ("GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0", "GIT_CONFIG_COUNT"):
        env.pop(key, None)

    plan = steps(skip_tuist_install=args.skip_tuist_install)
    if args.fast:
        plan = [s for s in plan if not s.fast_skip]

    if args.list:
        for step in plan:
            print(f"- {step.name}: {' '.join(step.command)}")
        return 0

    if not shutil.which("swift"):
        print("error: 'swift' not found in PATH", file=sys.stderr)
        return 2
    if any(step.command and step.command[0] == "cargo" for step in plan) and not shutil.which(
        "cargo"
    ):
        print("error: 'cargo' not found in PATH (required for Slint steps)", file=sys.stderr)
        return 2

    failures: list[str] = []
    total = 0.0
    for step in plan:
        ok, elapsed = run_step(step, env)
        total += elapsed
        if not ok:
            failures.append(step.name)
            break  # fail fast like CI

    print(f"\nTotal: {total:.1f}s")
    if failures:
        print(f"\033[1;31mFAIL: {failures[0]}\033[0m")
        return 1
    print("\033[1;32mAll CI steps passed locally.\033[0m")
    return 0


if __name__ == "__main__":
    sys.exit(main())
