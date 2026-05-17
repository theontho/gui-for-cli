"""Command-line interface for the platform runner."""

from __future__ import annotations

import argparse
import subprocess
import sys
import unicodedata

from .core import REPO_ROOT, Runner
from .registry import OPERATIONS, SUITES


ACTIONS = tuple(OPERATIONS)
LIST_CAPABILITIES = ACTIONS
HEADER_LABELS = {
    "release-build": ("release", "build"),
    "benchmark": ("bench", "mark"),
    "screenshot": ("screen", "shot"),
}


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

    columns = sorted_capability_columns(platform_actions, suite_actions)
    print_capability_table("platforms", platform_actions, columns)
    print_capability_table("suites", suite_actions, columns)
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


def sorted_capability_columns(*tables: dict[str, set[str]]) -> tuple[str, ...]:
    counts = {
        action: sum(action in actions for table in tables for actions in table.values())
        for action in LIST_CAPABILITIES
    }
    return tuple(sorted(LIST_CAPABILITIES, key=lambda action: -counts[action]))


def print_capability_table(
    title: str, capabilities: dict[str, set[str]], columns: tuple[str, ...]
) -> None:
    print(f"{title}:")
    if not capabilities:
        print("  (none)")
        return

    headers = ("name", *(HEADER_LABELS.get(action, action) for action in columns))
    rows = [
        (name, *("✅" if action in capabilities[name] else "❌" for action in columns))
        for name in sorted(capabilities)
    ]
    for line in render_table(headers, rows):
        print(f"  {line}")


Cell = str | tuple[str, ...]


def render_table(headers: tuple[Cell, ...], rows: list[tuple[str, ...]]) -> list[str]:
    widths = [
        max(cell_width(row[column]) for row in (headers, *rows))
        for column in range(len(headers))
    ]

    header_lines = render_multiline_row(headers, widths)
    separator = "| " + " | ".join("-" * width for width in widths) + " |"
    return [*header_lines, separator, *(render_single_line_row(row, widths) for row in rows)]


def render_multiline_row(row: tuple[Cell, ...], widths: list[int]) -> list[str]:
    row_lines = [cell_lines(cell) for cell in row]
    height = max(len(lines) for lines in row_lines)
    rendered = []
    for line_index in range(height):
        cells = [
            pad_cell(lines[line_index] if line_index < len(lines) else "", widths[index])
            for index, lines in enumerate(row_lines)
        ]
        rendered.append("| " + " | ".join(cells) + " |")
    return rendered


def render_single_line_row(row: tuple[str, ...], widths: list[int]) -> str:
    cells = [pad_cell(cell, widths[index]) for index, cell in enumerate(row)]
    return "| " + " | ".join(cells) + " |"


def cell_lines(value: Cell) -> tuple[str, ...]:
    if isinstance(value, str):
        return (value,)
    return value


def cell_width(value: Cell) -> int:
    return max(display_width(line) for line in cell_lines(value))


def pad_cell(value: str, width: int) -> str:
    return value + " " * (width - display_width(value))


def display_width(value: str) -> int:
    width = 0
    for char in value:
        if unicodedata.combining(char) or unicodedata.category(char) == "Cf":
            continue
        width += 2 if unicodedata.east_asian_width(char) in ("F", "W") else 1
    return width
