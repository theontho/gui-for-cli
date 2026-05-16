#!/usr/bin/env python3
"""Run the same checks GitHub Actions runs in CI, locally.

Usage:
  python3 tools/ci/ci_local.py            # run all CI steps
  python3 tools/ci/ci_local.py --fast     # skip iOS build (slowest step)
  python3 tools/ci/ci_local.py --list     # list steps without running

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

REPO_ROOT = Path(__file__).resolve().parents[2]
APPLE_DIR = "platform/apple"
APPLE_WORKSPACE = f"{APPLE_DIR}/GUIForCLI.xcworkspace"
APPLE_DERIVED_DATA = f"{APPLE_DIR}/DerivedData"
SWIFT_FORMAT_PATHS = [
    f"{APPLE_DIR}/Package.swift",
    f"{APPLE_DIR}/Project.swift",
    f"{APPLE_DIR}/Tuist.swift",
    f"{APPLE_DIR}/shared/Package.swift",
    f"{APPLE_DIR}/shared/Sources",
    f"{APPLE_DIR}/shared/Tests",
    f"{APPLE_DIR}/shared/app",
    f"{APPLE_DIR}/swiftui",
    f"{APPLE_DIR}/exp",
    "scripts",
]
SWIFT_GIT_ENV = {
    "GIT_CONFIG_COUNT": "1",
    "GIT_CONFIG_KEY_0": "safe.bareRepository",
    "GIT_CONFIG_VALUE_0": "all",
}


@dataclass
class Step:
    name: str
    command: list[str]
    groups: tuple[str, ...]
    fast_skip: bool = False  # skipped in --fast mode
    optional: bool = False  # missing tools yield warning, not failure


def steps(skip_tuist_install: bool) -> list[Step]:
    out: list[Step] = [
        Step(
            "swift package resolve",
            ["swift", "package", "--package-path", APPLE_DIR, "resolve"],
            ("apple",),
        ),
        Step(
            "swift format lint",
            [
                "swift",
                "format",
                "lint",
                "--recursive",
                *SWIFT_FORMAT_PATHS,
            ],
            ("apple",),
        ),
        Step("lint locales", ["python3", "tools/localization/lint_locales.py", "--strict"], ("apple",)),
        Step(
            "validate example bundles",
            [
                "swift",
                "run",
                "--package-path",
                APPLE_DIR,
                "gui-for-cli",
                "bundle",
                "validate",
                "--strict",
                "examples/WGSExtract",
            ],
            ("apple",),
        ),
        Step("swift test", ["swift", "test", "--package-path", APPLE_DIR, "--parallel"], ("apple",)),
        Step("build CLI release", ["swift", "build", "--package-path", APPLE_DIR, "-c", "release"], ("apple",)),
        Step("CLI smoke test", ["swift", "run", "--package-path", APPLE_DIR, "gui-for-cli", "--version"], ("apple",)),
        Step("gtk4 check", ["make", "test-gtk4"], ("rust",)),
        Step("slint test", ["cargo", "test", "--manifest-path", "exp-platform/rust/slint/Cargo.toml"], ("rust",)),
        Step("raygui test", ["cargo", "test", "--manifest-path", "exp-platform/rust/raygui/Cargo.toml"], ("rust",)),
        Step(
            "raygui bundle smoke",
            [
                "cargo",
                "run",
                "--manifest-path",
                "exp-platform/rust/raygui/Cargo.toml",
                "--release",
                "--",
                "--check",
            ],
            ("rust",),
        ),
        Step(
            "slint benchmark smoke",
            [
                "cargo",
                "run",
                "--manifest-path",
                "exp-platform/rust/slint/Cargo.toml",
                "--release",
                "--",
                "--benchmark",
                "--once",
            ],
            ("rust",),
        ),
        Step("imgui test", ["cargo", "test", "--manifest-path", "exp-platform/rust/imgui/Cargo.toml"], ("rust",)),
        Step("iced test", ["make", "test-iced"], ("rust",)),
        Step("makepad test", ["make", "test-makepad"], ("rust",)),
        Step("egui test", ["make", "test-egui"], ("rust",)),
        Step("dioxus check", ["cargo", "check", "--manifest-path", "exp-platform/rust/dioxus-shell/Cargo.toml"], ("rust",)),
        Step("python renderer tests", ["make", "test-python"], ("python",)),
        Step("qt qml source validation", ["make", "test-qt-qml"], ("cpp",)),
        Step(
            "imgui benchmark smoke",
            [
                "cargo",
                "run",
                "--manifest-path",
                "exp-platform/rust/imgui/Cargo.toml",
                "--release",
                "--",
                "--benchmark",
                "--once",
            ],
            ("rust",),
        ),
    ]
    if not skip_tuist_install:
        out.append(
            Step(
                "tuist install",
                ["sh", "-c", "cd platform/apple && ../../scripts/tuist.sh install"],
                ("apple",),
            )
        )
    out += [
        Step(
            "tuist generate",
            ["sh", "-c", "cd platform/apple && ../../scripts/tuist.sh generate --no-open"],
            ("apple",),
        ),
        Step(
            "build iOS app",
            [
                "xcodebuild",
                "-workspace",
                APPLE_WORKSPACE,
                "-scheme",
                "GUIForCLIiOS",
                "-derivedDataPath",
                APPLE_DERIVED_DATA,
                "-destination",
                "generic/platform=iOS Simulator",
                "build",
                "CODE_SIGNING_ALLOWED=NO",
            ],
            ("apple",),
            fast_skip=True,
        ),
        Step(
            "build macOS app",
            [
                "xcodebuild",
                "-workspace",
                APPLE_WORKSPACE,
                "-scheme",
                "GUIForCLIMac",
                "-derivedDataPath",
                APPLE_DERIVED_DATA,
                "build",
                "CODE_SIGNING_ALLOWED=NO",
            ],
            ("apple",),
        ),
    ]
    return out


def run_step(step: Step, env: dict[str, str]) -> tuple[bool, float]:
    print(f"\n\033[1;36m▶ {step.name}\033[0m")
    print(f"  $ {' '.join(step.command)}")
    start = time.monotonic()
    try:
        step_env = env.copy()
        if step.command and step.command[0] == "swift":
            step_env.update(SWIFT_GIT_ENV)
        proc = subprocess.run(step.command, cwd=REPO_ROOT, env=step_env, check=False)
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
    parser.add_argument(
        "--group",
        action="append",
        choices=("apple", "rust", "cpp", "python"),
        help="Run only one CI step group. May be passed more than once.",
    )
    args = parser.parse_args()

    env = os.environ.copy()
    # Strip env vars that break SPM resolution under xcodebuild on macOS.
    for key in ("GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0", "GIT_CONFIG_COUNT"):
        env.pop(key, None)

    plan = steps(skip_tuist_install=args.skip_tuist_install)
    if args.group:
        selected = set(args.group)
        plan = [s for s in plan if selected.intersection(s.groups)]
    if args.fast:
        plan = [s for s in plan if not s.fast_skip]

    if args.list:
        for step in plan:
            print(f"- {step.name}: {' '.join(step.command)}")
        return 0

    if any(step.command and step.command[0] == "swift" for step in plan) and not shutil.which("swift"):
        print("error: 'swift' not found in PATH", file=sys.stderr)
        return 2
    if any(step.command and step.command[0] == "cargo" for step in plan) and not shutil.which(
        "cargo"
    ):
        print(
            "error: 'cargo' not found in PATH (required for Slint/Raygui/ImGui steps)",
            file=sys.stderr,
        )
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
