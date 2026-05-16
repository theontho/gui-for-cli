#!/usr/bin/env python3
"""iOS Simulator accessibility smoke test.

Wraps ``axe describe-ui`` (the homebrew ``axe`` tool) against a booted
iOS Simulator running ``GUIForCLI.app`` and emits the same kind of
report as ``ax_smoke.py``:

  * total accessible nodes and role distribution
  * interactive controls missing every label/help/title — these are
    accessibility holes
  * count of disabled buttons (sanity check that the "Run" buttons are
    disabled on iOS per ActionButton's isUnsupportedPlatform guard)

Exit code: 0 on success, 1 if no simulator is booted / axe is missing,
2 if there are unlabeled interactive controls.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from collections import Counter

INTERACTIVE = {
    "AXButton", "AXTextField", "AXSwitch", "AXSlider",
    "AXPopUpButton", "AXLink", "AXCheckBox",
}


def walk(node, depth=0):
    if isinstance(node, dict):
        yield depth, node
        for child in node.get("children") or []:
            yield from walk(child, depth + 1)
    elif isinstance(node, list):
        for child in node:
            yield from walk(child, depth)


def label(node) -> str:
    parts = [
        node.get("AXLabel") or "",
        node.get("title") or "",
        node.get("help") or "",
    ]
    value = node.get("AXValue")
    if isinstance(value, str):
        parts.append(value)
    return " ".join(p for p in parts if p)


def identifier(node) -> str:
    return node.get("AXUniqueId") or node.get("identifier") or ""


def booted_udid() -> str | None:
    try:
        out = subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "booted"], text=True
        )
    except subprocess.CalledProcessError:
        return None
    for line in out.splitlines():
        if "(Booted)" in line and "(" in line:
            # format: "    iPhone 17 Pro (UDID) (Booted)"
            try:
                return line.split("(")[1].split(")")[0].strip()
            except IndexError:
                continue
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", default=None,
                        help="Simulator UDID; defaults to the first booted simulator.")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    if shutil.which("axe") is None:
        print("ERROR: 'axe' CLI not found (brew install cameroncooke/axe/axe)",
              file=sys.stderr)
        return 1

    udid = args.udid or booted_udid()
    if udid is None:
        print("ERROR: no booted iOS simulator", file=sys.stderr)
        return 1
    print(f"Probing iOS simulator {udid}")

    try:
        raw = subprocess.check_output(["axe", "describe-ui", "--udid", udid])
    except subprocess.CalledProcessError as exc:
        print(f"ERROR: axe describe-ui failed: {exc}", file=sys.stderr)
        return 1
    data = json.loads(raw)

    nodes = list(walk(data))
    print(f"Total iOS AX nodes: {len(nodes)}")

    roles = Counter(n.get("role", "?") for _, n in nodes)
    print("Roles: " + ", ".join(f"{r}={c}" for r, c in roles.most_common(8)))

    holes = [
        (d, n) for d, n in nodes
        if n.get("role") in INTERACTIVE and not label(n)
    ]
    print(f"Unlabeled interactive controls: {len(holes)}")
    for d, n in holes[:20]:
        print(f"  [{n.get('role')}] depth={d}")

    disabled = [n for _, n in nodes
                if n.get("role") == "AXButton" and n.get("enabled") is False]
    print(f"Disabled buttons (expected for Run on iOS): {len(disabled)}")
    for n in disabled[:10]:
        print(f"  [{label(n)[:80]!r}]")

    namespaces = ("control.", "action.", "section.", "page.", "option.")
    annotated = [n for _, n in nodes if identifier(n).startswith(namespaces)]
    print(f"Manifest-annotated AX nodes: {len(annotated)}")
    if annotated:
        by_ns = Counter(identifier(i).split(".", 1)[0] for i in annotated)
        print("  by namespace: " + ", ".join(f"{k}={v}" for k, v in by_ns.most_common()))

    if args.verbose:
        print("\n--- Interactive controls ---")
        for _, n in nodes:
            if n.get("role") in INTERACTIVE:
                print(f"  [{n.get('role')}] enabled={n.get('enabled')} "
                      f"label={label(n)[:80]!r}")

    return 2 if holes else 0


if __name__ == "__main__":
    sys.exit(main())
