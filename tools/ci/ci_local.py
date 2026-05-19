#!/usr/bin/env python3
"""Run the same checks GitHub Actions runs in CI, locally.

Usage:
  uv run python tools/ci/ci_local.py                 # run all CI steps
  uv run python tools/ci/ci_local.py --fast          # skip iOS build (slowest step)
  uv run python tools/ci/ci_local.py --fast --pre-push
  uv run python tools/ci/ci_local.py --changed --list

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

import ci_changed_paths

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON = os.environ.get("PYTHON", sys.executable)
APPLE_DIR = "platform/apple"
APPLE_WORKSPACE = f"{APPLE_DIR}/GUIForCLI.xcworkspace"
APPLE_DERIVED_DATA = f"{APPLE_DIR}/DerivedData"
LOCAL_GROUPS = ("apple", "typescript", "rust", "go", "cpp", "dotnet", "python", "windows", "meta")
ALL_ZERO_SHA = "0" * 40
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
        Step("lint locales", [PYTHON, "tools/localization/lint_locales.py", "--strict"], ("apple",)),
        Step(
            "localization tool tests",
            [PYTHON, "-m", "unittest", "discover", "-s", "tools/localization/tests"],
            ("apple", "meta"),
        ),
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
        Step("typescript tests", ["npm", "--prefix", "platform/typescript", "test"], ("typescript",)),
        Step("gtk4 check", ["make", "test", "PLATFORM=gtk4"], ("rust",)),
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
        Step("iced test", ["make", "test", "PLATFORM=iced"], ("rust",)),
        Step("makepad test", ["make", "test", "PLATFORM=makepad"], ("rust",)),
        Step("egui test", ["make", "test", "PLATFORM=egui"], ("rust",)),
        Step("dioxus check", ["cargo", "check", "--manifest-path", "exp-platform/rust/dioxus-shell/Cargo.toml"], ("rust",)),
        Step("python renderer tests", ["make", "test", "PLATFORM=python"], ("python",)),
        Step("qt qml source validation", ["make", "test", "PLATFORM=qt-qml"], ("cpp",)),
        Step(
            "go renderer tests",
            [
                "sh",
                "-c",
                "cd exp-platform/go/gio && go test ./... && "
                "cd ../fyne && GOTOOLCHAIN=go1.25.0 go test ./...",
            ],
            ("go",),
        ),
        Step("avalonia tests", ["make", "test", "PLATFORM=avalonia"], ("dotnet",)),
        Step(
            "validate CI scripts and tools",
            [
                PYTHON,
                "-m",
                "compileall",
                "-q",
                "scripts/setup-hooks.py",
                "tools/ci",
                "tools/localization",
                "tools/packaging/posix",
                "tools/platform.py",
                "tools/platform_runner",
            ],
            ("meta",),
        ),
        Step("CI classifier tests", [PYTHON, "-m", "unittest", "discover", "-s", "tools/ci/tests"], ("meta",)),
        Step("platform runner list", [PYTHON, "tools/platform.py", "list"], ("meta",)),
        Step(
            "platform runner list benchmark",
            [PYTHON, "tools/platform.py", "list", "benchmark"],
            ("meta",),
        ),
        Step("make help", ["make", "help"], ("meta",)),
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


def git_stdout(args: list[str]) -> str | None:
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=REPO_ROOT,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except subprocess.CalledProcessError:
        return None
    return result.stdout.strip()


def default_branch_ref() -> str | None:
    origin_head = git_stdout(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"])
    if origin_head:
        return origin_head
    for candidate in ("origin/main", "origin/master", "main", "master"):
        if git_stdout(["rev-parse", "--verify", "--quiet", candidate]):
            return candidate
    return None


def changed_paths_for_range(base: str, head: str) -> list[str] | None:
    return ci_changed_paths.git_changed_paths(base, head)


def changed_paths_from_pre_push(stdin: str) -> list[str] | None:
    paths: set[str] = set()
    saw_ref = False
    for line in stdin.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        _, local_sha, _, remote_sha = parts[:4]
        if not local_sha or local_sha == ALL_ZERO_SHA:
            continue
        saw_ref = True
        base = remote_sha
        if not base or base == ALL_ZERO_SHA:
            default_ref = default_branch_ref()
            base = git_stdout(["merge-base", local_sha, default_ref]) if default_ref else None
        if not base:
            return None
        changed = changed_paths_for_range(base, local_sha)
        if changed is None:
            return None
        paths.update(changed)
    if not saw_ref:
        return changed_paths_against_upstream()
    return sorted(paths)


def changed_paths_against_upstream() -> list[str] | None:
    upstream = git_stdout(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"])
    if upstream:
        return changed_paths_for_range(upstream, "HEAD")
    default_ref = default_branch_ref()
    base = git_stdout(["merge-base", "HEAD", default_ref]) if default_ref else None
    return changed_paths_for_range(base, "HEAD") if base else None


def changed_paths_from_args(args: argparse.Namespace) -> list[str] | None:
    if args.path:
        return [ci_changed_paths.normalize_path(path) for path in args.path]
    if args.pre_push:
        if sys.stdin.isatty():
            raise SystemExit(
                "--pre-push expects refs on stdin; use --changed with --path/--base for manual checks."
            )
        return changed_paths_from_pre_push(sys.stdin.read())
    if args.base:
        return changed_paths_for_range(args.base, args.head)
    return changed_paths_against_upstream()


def selected_groups_from_changes(paths: list[str]) -> tuple[str, ...]:
    classified = ci_changed_paths.classify(paths)
    return tuple(group for group in LOCAL_GROUPS if classified.get(group, False))


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
        choices=LOCAL_GROUPS,
        help="Run only one CI step group. May be passed more than once.",
    )
    parser.add_argument(
        "--changed",
        action="store_true",
        help="Select CI step groups from changed paths instead of running every group.",
    )
    parser.add_argument("--base", help="Base git revision for --changed selection.")
    parser.add_argument("--head", default="HEAD", help="Head git revision for --changed selection.")
    parser.add_argument(
        "--path",
        action="append",
        help="Explicit changed path for --changed selection. May be passed more than once.",
    )
    parser.add_argument(
        "--pre-push",
        action="store_true",
        help="Read git pre-push refs from stdin and select only affected step groups.",
    )
    args = parser.parse_args()

    env = os.environ.copy()
    # Strip env vars that break SPM resolution under xcodebuild on macOS.
    for key in ("GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0", "GIT_CONFIG_COUNT"):
        env.pop(key, None)

    plan = steps(skip_tuist_install=args.skip_tuist_install)
    selected_groups = tuple(args.group or ())
    if args.changed or args.pre_push:
        changed_paths = changed_paths_from_args(args)
        if changed_paths is None:
            print("error: could not determine changed paths", file=sys.stderr)
            return 2
        changed_groups = selected_groups_from_changes(changed_paths)
        if changed_groups:
            print("Selected changed groups: " + ", ".join(changed_groups))
        else:
            print("No local CI steps selected for changed paths.")
        if selected_groups:
            requested = set(selected_groups)
            selected_groups = tuple(group for group in changed_groups if group in requested)
        else:
            selected_groups = changed_groups
    if selected_groups:
        selected = set(selected_groups)
        plan = [s for s in plan if selected.intersection(s.groups)]
        if not plan:
            print("No local CI steps available for selected groups: " + ", ".join(selected_groups))
    elif args.changed or args.pre_push:
        plan = []
    if args.fast:
        plan = [s for s in plan if not s.fast_skip]

    if args.list:
        if plan:
            for step in plan:
                print(f"- {step.name}: {' '.join(step.command)}")
        else:
            print("- no local CI steps selected")
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
