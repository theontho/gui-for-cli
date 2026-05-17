"""Command-line interface for the platform runner."""

from __future__ import annotations

import argparse
import subprocess
import sys
import unicodedata

from .core import REPO_ROOT, Runner
from .registry import OPERATIONS, SUITES


ACTIONS = tuple(OPERATIONS)
LIST_CAPABILITIES = (
    "setup",
    "lint",
    "format",
    "build",
    "run",
    "test",
    "package",
    "release-build",
    "clean",
    "benchmark",
    "screenshot",
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Run platform setup/lint/format/build/run/test/clean/benchmark/screenshot/package tasks."
        ),
        epilog=(
            "Examples:\n"
            "  tools/platform.py build swiftui-macos\n"
            "  tools/platform.py run webui\n"
            "  tools/platform.py lint stable\n"
            "  tools/platform.py test stable\n"
            "  tools/platform.py release-build stable\n"
            "  tools/platform.py package webui"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--dry-run", action="store_true", help="Print commands without running them.")
    subcommands = parser.add_subparsers(dest="command", required=True)

    list_parser = subcommands.add_parser("list", help="List actions, suites, and platforms.")
    list_parser.add_argument("action", nargs="?", choices=ACTIONS, help="Limit listing to one action.")
    list_parser.set_defaults(func=list_items)

    for action in ACTIONS:
        action_parser = subcommands.add_parser(action, help=f"Run {action} for platforms or suites.")
        action_parser.add_argument(
            "items",
            nargs=argparse.REMAINDER if action in ("benchmark", "screenshot") else "*",
            help="Platform names or suites.",
        )
        action_parser.set_defaults(func=run_action, action=action)

    args = parser.parse_args()
    return args.func(args)


def run_action(args: argparse.Namespace) -> int:
    items = args.items
    if args.action in ("benchmark", "screenshot") and items and should_pass_through(args.action, items):
        return run_benchmark_tool(args.action, items, dry_run=args.dry_run)
    if not items:
        default_suite = SUITES.get(args.action, {}).get("default")
        if default_suite is None:
            raise SystemExit(f"{args.action} requires at least one platform or suite")
        items = ["default"]
    Runner(OPERATIONS, SUITES, dry_run=args.dry_run).run(args.action, items)
    return 0


def should_pass_through(action: str, items: list[str]) -> bool:
    if any(item.startswith("-") for item in items):
        return True
    runner = Runner(OPERATIONS, SUITES)
    try:
        runner.expand_items(action, items)
    except SystemExit:
        return True
    return False


def run_benchmark_tool(action: str, items: list[str], *, dry_run: bool) -> int:
    command = [sys.executable, "tools/benchmarking/benchmark.py", action, *items]
    if dry_run and "--dry-run" not in items:
        command.append("--dry-run")
    print(" ".join(command))
    subprocess.run(command, cwd=REPO_ROOT, check=True)
    return 0


def list_items(args: argparse.Namespace) -> int:
    platform_actions = platform_capabilities()
    suite_actions = suite_capabilities()
    if args.action:
        platform_actions = {
            name: actions for name, actions in platform_actions.items() if args.action in actions
        }
        suite_actions = {
            name: actions for name, actions in suite_actions.items() if args.action in actions
        }

    print_capability_table("platforms", platform_actions)
    print_capability_table("suites", suite_actions)
    return 0


def platform_capabilities() -> dict[str, set[str]]:
    capabilities: dict[str, set[str]] = {}
    for action in LIST_CAPABILITIES:
        for name in OPERATIONS[action]:
            capabilities.setdefault(name, set()).add(action)
    return capabilities


def suite_capabilities() -> dict[str, set[str]]:
    capabilities: dict[str, set[str]] = {}
    for action in LIST_CAPABILITIES:
        for name in SUITES.get(action, {}):
            capabilities.setdefault(name, set()).add(action)
    return capabilities


def print_capability_table(title: str, capabilities: dict[str, set[str]]) -> None:
    print(f"{title}:")
    if not capabilities:
        print("  (none)")
        return

    headers = ("name", *LIST_CAPABILITIES)
    rows = [
        (name, *("✅" if action in capabilities[name] else "❌" for action in LIST_CAPABILITIES))
        for name in sorted(capabilities)
    ]
    for line in render_table(headers, rows):
        print(f"  {line}")


def render_table(headers: tuple[str, ...], rows: list[tuple[str, ...]]) -> list[str]:
    widths = [
        max(display_width(row[column]) for row in (headers, *rows))
        for column in range(len(headers))
    ]

    def render_row(row: tuple[str, ...]) -> str:
        cells = [pad_cell(cell, widths[index]) for index, cell in enumerate(row)]
        return "| " + " | ".join(cells) + " |"

    separator = "| " + " | ".join("-" * width for width in widths) + " |"
    return [render_row(headers), separator, *(render_row(row) for row in rows)]


def pad_cell(value: str, width: int) -> str:
    return value + " " * (width - display_width(value))


def display_width(value: str) -> int:
    width = 0
    for char in value:
        if unicodedata.combining(char) or unicodedata.category(char) == "Cf":
            continue
        width += 2 if unicodedata.east_asian_width(char) in ("F", "W") else 1
    return width
