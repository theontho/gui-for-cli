#!/usr/bin/env python3
"""Unified CLI for GUI for CLI benchmarks and screenshots."""

from __future__ import annotations

import argparse

from benchmark_catalog import COMMAND_ORDER, COMMANDS, SCREENSHOT_MAP, SCREENSHOT_ORDER, SCREENSHOT_SUITES, SUITES
from benchmark_core import context_from_args, run


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)

    list_parser = subcommands.add_parser("list", help="List benchmark and screenshot commands.")
    list_parser.set_defaults(func=list_items)

    benchmark_parser = subcommands.add_parser("benchmark", help="Run benchmark suites or commands.")
    add_item_argument(benchmark_parser, "Suite or benchmark names, e.g. macos, webui-browser, benchmark-swiftui-macos.")
    benchmark_parser.add_argument("--samples", type=int, help="Set benchmark sample count.")
    benchmark_parser.add_argument(
        "--headless-browser",
        action="store_true",
        help="Run the Browser Web UI benchmark with Playwright Chromium hidden. Default is visible UX.",
    )
    benchmark_parser.add_argument(
        "--no-focus",
        action="store_true",
        help="Preserve the current foreground app when launching benchmark apps where supported.",
    )
    benchmark_parser.add_argument("--dry-run", action="store_true", help="Print commands without running them.")
    benchmark_parser.set_defaults(func=benchmark_items)

    screenshot_parser = subcommands.add_parser("screenshot", help="Capture screenshot suites or surfaces.")
    add_item_argument(screenshot_parser, "Suite, benchmark, or screenshot surface names. Defaults to macos.", required=False)
    screenshot_parser.add_argument(
        "--capture-only",
        help="Additional comma-separated raw screenshot surface names for migration/debugging.",
    )
    screenshot_parser.add_argument("--dry-run", action="store_true", help="Print commands without running them.")
    screenshot_parser.set_defaults(func=screenshot_items)

    args = parser.parse_args()
    return args.func(args)


def list_items(_: argparse.Namespace) -> int:
    print("Benchmark suites:")
    for name, suite in SUITES.items():
        print(f"  {name:18} {' '.join(suite.items):70} {suite.description}")
    print("\nBenchmark commands:")
    for name in COMMAND_ORDER:
        command = COMMANDS[name]
        print(f"  {name:18} {command.description}")
    print(f"  {'mojo':18} {COMMANDS['mojo'].description}")
    print(f"  {'flutter':18} {COMMANDS['flutter'].description}")
    print(f"  {'startup-sequential':18} {COMMANDS['startup-sequential'].description}")
    print("\nScreenshot suites:")
    for name, suite in SCREENSHOT_SUITES.items():
        print(f"  {name:18} {' '.join(suite.items):70} {suite.description}")
    print("\nScreenshot surfaces:")
    for name in SCREENSHOT_ORDER:
        print(f"  {name}")
    return 0


def add_item_argument(parser: argparse.ArgumentParser, help_text: str, *, required: bool = True) -> None:
    parser.add_argument("items", nargs="+" if required else "*", help=help_text)


def benchmark_items(args: argparse.Namespace) -> int:
    ctx = context_from_args(args)
    for item in expand_benchmark_items(args.items):
        COMMANDS[item].run(ctx)
    return 0


def screenshot_items(args: argparse.Namespace) -> int:
    ctx = context_from_args(args)
    surfaces = expand_screenshot_items(args.items or ["macos"])
    if args.capture_only:
        surfaces.extend(item.strip() for item in args.capture_only.split(",") if item.strip())
    capture_only = ",".join(dict.fromkeys(surfaces))
    run(ctx, ["python3", "tools/benchmarking/capture_macos_screenshots.py"], env={"CAPTURE_ONLY": capture_only})
    return 0


def expand_benchmark_items(items: list[str]) -> list[str]:
    expanded: list[str] = []
    for item in items:
        normalized = normalize_benchmark_item(item)
        suite = SUITES.get(normalized)
        if suite and not (len(suite.items) == 1 and suite.items[0] == normalized and normalized in COMMANDS):
            expanded.extend(expand_benchmark_items(list(suite.items)))
            continue
        if normalized not in COMMANDS:
            choices = ", ".join(sorted(set(SUITES) | set(COMMANDS)))
            raise SystemExit(f"unknown benchmark item: {item}\nKnown items: {choices}")
        expanded.append(normalized)
    return expanded


def expand_screenshot_items(items: list[str]) -> list[str]:
    expanded: list[str] = []
    for item in items:
        normalized = normalize_screenshot_item(item)
        suite = SCREENSHOT_SUITES.get(normalized)
        if suite:
            expanded.extend(expand_screenshot_items(list(suite.items)))
            continue
        surface = SCREENSHOT_MAP.get(normalized, normalized)
        if surface not in SCREENSHOT_ORDER:
            choices = ", ".join(sorted(set(SCREENSHOT_SUITES) | set(SCREENSHOT_MAP) | set(SCREENSHOT_ORDER)))
            raise SystemExit(f"unknown screenshot item: {item}\nKnown items: {choices}")
        expanded.append(surface)
    return expanded


def normalize_benchmark_item(item: str) -> str:
    aliases = {
        "benchmark-all": "benchmark-all",
        "benchmark-macos-all": "macos",
        "benchmark-mojo": "mojo",
        "benchmark-flutter": "flutter",
    }
    if item in aliases:
        return aliases[item]
    if item.startswith("benchmark-"):
        return item.removeprefix("benchmark-")
    return item


def normalize_screenshot_item(item: str) -> str:
    aliases = {
        "screenshot": "macos",
        "screenshots": "macos",
    }
    if item in aliases:
        return aliases[item]
    if item.startswith("screenshot-"):
        return item.removeprefix("screenshot-")
    if item.startswith("benchmark-"):
        return normalize_benchmark_item(item)
    return item


if __name__ == "__main__":
    raise SystemExit(main())
