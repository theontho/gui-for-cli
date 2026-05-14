#!/usr/bin/env python3
"""Classify changed paths into CI platform groups."""

from __future__ import annotations

import argparse
import fnmatch
import os
import subprocess
import sys
from pathlib import Path

GROUPS = ("apple", "typescript", "rust", "go", "cpp", "dotnet", "python", "windows", "meta")

GLOBAL_PATTERNS = (
    ".github/workflows/ci.yml",
    ".github/workflows/coverage.yml",
    "scripts/ci-changed-paths.py",
    "scripts/ci-local.py",
)

GROUP_PATTERNS = {
    "apple": (
        "platform/apple/**",
        "examples/**",
        "docs/schema/manifest.schema.json",
        "scripts/ax-smoke.py",
        "scripts/ax-smoke-ios.py",
        "scripts/lint-locales.py",
        "scripts/tuist.sh",
    ),
    "typescript": (
        "platform/typescript/**",
        "examples/**",
        "docs/schema/manifest.schema.json",
    ),
    "rust": (
        "exp-platform/rust/**",
        "examples/**",
        "docs/schema/manifest.schema.json",
    ),
    "go": (
        "exp-platform/go/**",
        "examples/**",
        "docs/schema/manifest.schema.json",
        "scripts/benchmark-fyne-macos.py",
        "scripts/benchmark-gio-macos.py",
    ),
    "cpp": (
        "exp-platform/cpp/**",
        "examples/**",
        "docs/schema/manifest.schema.json",
    ),
    "dotnet": (
        "exp-platform/dotnet/**",
        "exp-platform/windows/dotnet/GUIForCLIWindows.Core/**",
        "exp-platform/windows/dotnet/GUIForCLIWindows.CoreTests/**",
        "examples/**",
        "docs/schema/manifest.schema.json",
    ),
    "python": (
        "exp-platform/python/**",
        "examples/**",
        "docs/schema/manifest.schema.json",
    ),
    "windows": (
        ".github/workflows/windows.yml",
        "exp-platform/windows/dotnet/**",
        "exp-platform/go/gio/**",
        "exp-platform/rust/dioxus-shell/**",
        "platform/typescript/**",
        "examples/**",
        "docs/schema/manifest.schema.json",
        "make.ps1",
        "scripts/package-windows-gio.ps1",
        "scripts/package-windows-msix.ps1",
        "scripts/package-windows-bootstrap.ps1",
        "scripts/windows-ax-smoke.ps1",
    ),
    "meta": (
        ".github/workflows/**",
        ".github/dependabot.yml",
        "Makefile",
        "make.ps1",
        "scripts/**",
    ),
}


def git_changed_paths(base: str | None, head: str | None) -> list[str] | None:
    # Initial pushes can report the previous ref as an all-zero SHA.
    if not base or not head or set(base) == {"0"}:
        return None
    try:
        # The command shape is fixed and base/head come from trusted CI refs.
        result = subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=ACMRTD", f"{base}...{head}"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except subprocess.CalledProcessError as error:
        print(error.stderr, file=sys.stderr, end="")
        return None
    return [line for line in result.stdout.splitlines() if line]


def matches(path: str, patterns: tuple[str, ...]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def normalize_path(path: str) -> str:
    return "/".join(part for part in path.replace("\\", "/").split("/") if part)


def classify(paths: list[str] | None, force_all: bool = False) -> dict[str, bool]:
    if force_all or paths is None:
        return {group: True for group in GROUPS}

    global_change = any(matches(path, GLOBAL_PATTERNS) for path in paths)
    return {
        group: global_change or any(matches(path, GROUP_PATTERNS[group]) for path in paths)
        for group in GROUPS
    }


def write_github_outputs(outputs: dict[str, bool], output_path: Path) -> None:
    with output_path.open("a", encoding="utf-8") as handle:
        for group in GROUPS:
            handle.write(f"{group}={str(outputs[group]).lower()}\n")
        handle.write(f"any={str(any(outputs.values())).lower()}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="Changed paths to classify.")
    parser.add_argument("--base", help="Base git revision for diff classification.")
    parser.add_argument("--head", help="Head git revision for diff classification.")
    parser.add_argument("--all", action="store_true", help="Mark every platform group changed.")
    parser.add_argument("--github-output", type=Path, help="Write GitHub Actions outputs to this file.")
    args = parser.parse_args()

    paths = [normalize_path(path) for path in args.paths] if args.paths else git_changed_paths(args.base, args.head)
    outputs = classify(paths, force_all=args.all)

    for group in GROUPS:
        print(f"{group}={str(outputs[group]).lower()}")

    github_output = args.github_output or os.environ.get("GITHUB_OUTPUT")
    if github_output:
        write_github_outputs(outputs, Path(github_output))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
