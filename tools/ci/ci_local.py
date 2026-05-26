#!/usr/bin/env python3
"""Run the same checks GitHub Actions runs in CI, locally.

Usage:
  uv run python tools/ci/ci_local.py                 # run all CI steps
  uv run python tools/ci/ci_local.py --fast          # skip long Apple tests and app generation/build steps
  uv run python tools/ci/ci_local.py --fast --pre-push
  uv run python tools/ci/ci_local.py --changed --list

Exit code mirrors the first failing step.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys

try:
    from .ci_local_changes import (
        changed_paths_against_upstream,
        changed_paths_for_range,
        changed_paths_from_args,
        changed_paths_from_pre_push,
        default_branch_ref,
        git_stdout,
        selected_groups_from_changes,
    )
    from .ci_local_model import (
        ALL_ZERO_SHA,
        APPLE_DERIVED_DATA,
        APPLE_DIR,
        APPLE_PLATFORMS,
        APPLE_WORKSPACE,
        CURRENT_OS,
        LOCAL_GROUPS,
        PYTHON,
        REPO_ROOT,
        SWIFT_FORMAT_PATHS,
        SWIFT_GIT_ENV,
        Step,
    )
    from .ci_local_runner import filter_supported_steps, run_step
    from .ci_local_steps import steps
except ImportError:  # pragma: no cover - script execution path
    from ci_local_changes import (
        changed_paths_against_upstream,
        changed_paths_for_range,
        changed_paths_from_args,
        changed_paths_from_pre_push,
        default_branch_ref,
        git_stdout,
        selected_groups_from_changes,
    )
    from ci_local_model import (
        ALL_ZERO_SHA,
        APPLE_DERIVED_DATA,
        APPLE_DIR,
        APPLE_PLATFORMS,
        APPLE_WORKSPACE,
        CURRENT_OS,
        LOCAL_GROUPS,
        PYTHON,
        REPO_ROOT,
        SWIFT_FORMAT_PATHS,
        SWIFT_GIT_ENV,
        Step,
    )
    from ci_local_runner import filter_supported_steps, run_step
    from ci_local_steps import steps


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fast",
        action="store_true",
        help="Skip long Apple tests and app project generation/build steps.",
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
    plan = filter_supported_steps(plan)

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
