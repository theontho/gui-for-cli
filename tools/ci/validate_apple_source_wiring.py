#!/usr/bin/env python3
"""Validate Apple SwiftPM/Tuist source wiring stays aligned."""

from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def require_contains(path: str, snippets: list[str]) -> list[str]:
    try:
        text = read(path)
    except OSError as error:
        return [f"{path}: unable to read ({error.strerror or error})"]
    missing = [snippet for snippet in snippets if snippet not in text]
    return [f"{path}: missing {snippet!r}" for snippet in missing]


def main() -> int:
    errors: list[str] = []
    errors += require_contains(
        "platform/apple/Package.swift",
        [
            'path: "shared/Sources/GUIForCLICore"',
            'resources: [.copy("Resources")]',
            'path: "shared/Sources/GUIForCLICLI"',
            'path: "shared/Tests/GUIForCLICoreTests"',
            'path: "shared/Tests/GUIForCLICLITests"',
        ],
    )
    errors += require_contains(
        "platform/apple/shared/Package.swift",
        [
            'path: "Sources/GUIForCLICore"',
            'resources: [.copy("Resources")]',
        ],
    )
    errors += require_contains(
        "platform/apple/Project.swift",
        [
            '.package(path: "shared")',
            '"shared/app/**/*.swift"',
            '"shared/app/Resources/**"',
            'let coreDependency: TargetDependency = .package(product: "GUIForCLICore")',
        ],
    )

    app_sources = sorted((REPO_ROOT / "platform/apple/shared/app").glob("**/*.swift"))
    core_sources = sorted((REPO_ROOT / "platform/apple/shared/Sources/GUIForCLICore").glob("**/*.swift"))
    cli_sources = sorted((REPO_ROOT / "platform/apple/shared/Sources/GUIForCLICLI").glob("**/*.swift"))
    if not app_sources:
        errors.append("platform/apple/shared/app: no shared app Swift sources found")
    if not core_sources:
        errors.append("platform/apple/shared/Sources/GUIForCLICore: no core Swift sources found")
    if not cli_sources:
        errors.append("platform/apple/shared/Sources/GUIForCLICLI: no CLI Swift sources found")

    if errors:
        print("Apple source wiring validation failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print("Apple source wiring is aligned.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
