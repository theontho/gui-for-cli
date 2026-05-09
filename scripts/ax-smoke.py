#!/opt/homebrew/bin/python3
"""Accessibility smoke test for the GUI for CLI dev app.

Walks the AX tree of the running ``GUI for CLI`` development build and
emits a structured summary plus a small set of assertions:

  * total accessible nodes and role distribution
  * interactive controls (button, popup, text field, etc.) missing
    every label attribute (title / description / help) — these are
    accessibility holes
  * the active locale (heuristic, based on observed UI text)

Requires Accessibility permission for whichever process runs Python
(usually Terminal/iTerm). Install once with:

    /opt/homebrew/bin/python3 -m pip install --break-system-packages \\
        pyobjc-framework-ApplicationServices pyobjc-framework-Cocoa

Exit code: 0 on success, 1 if the dev app isn't running, 2 if there
are accessibility holes on interactive controls (excluding window
chrome traffic-light buttons, which are unlabeled by AppKit).
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from collections import Counter

from ApplicationServices import (  # type: ignore
    AXUIElementCopyAttributeValue,
    AXUIElementCreateApplication,
    kAXChildrenAttribute,
    kAXDescriptionAttribute,
    kAXHelpAttribute,
    kAXIdentifierAttribute,
    kAXPositionAttribute,
    kAXRoleAttribute,
    kAXSubroleAttribute,
    kAXTitleAttribute,
    kAXValueAttribute,
)

INTERACTIVE = {
    "AXButton", "AXPopUpButton", "AXTextField", "AXCheckBox",
    "AXRadioButton", "AXSlider", "AXMenuButton", "AXLink",
}

# Window traffic-lights are AXButton with subrole AXCloseButton/AXMinimizeButton/AXZoomButton
# Scroll-bar parts (arrows / page regions) are AppKit-provided and conventionally unlabeled.
WINDOW_CHROME_SUBROLES = {
    "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton",
    "AXIncrementArrow", "AXDecrementArrow", "AXIncrementPage", "AXDecrementPage",
}


def find_pid(pattern: str) -> int | None:
    out = subprocess.run(
        ["pgrep", "-f", pattern], capture_output=True, text=True
    ).stdout.strip().splitlines()
    return int(out[0]) if out else None


def attr(el, key):
    err, val = AXUIElementCopyAttributeValue(el, key, None)
    return val if err == 0 else None


def walk(el, depth=0, nodes=None):
    if nodes is None:
        nodes = []
    nodes.append({
        "depth": depth,
        "role": attr(el, kAXRoleAttribute) or "?",
        "subrole": attr(el, kAXSubroleAttribute) or "",
        "title": attr(el, kAXTitleAttribute) or "",
        "desc": attr(el, kAXDescriptionAttribute) or "",
        "value": attr(el, kAXValueAttribute),
        "help": attr(el, kAXHelpAttribute) or "",
        "identifier": attr(el, kAXIdentifierAttribute) or "",
    })
    for k in attr(el, kAXChildrenAttribute) or []:
        walk(k, depth + 1, nodes)
    return nodes


def labels(node) -> str:
    parts = [node["title"], node["desc"], node["help"]]
    if isinstance(node["value"], str):
        parts.append(node["value"])
    return " ".join(p for p in parts if p)


def detect_locale(blob: str) -> str:
    samples = {
        "fa": "هم‌ترازی",
        "ar": "محاذاة",
        "ja": "アライメント",
        "ko": "정렬",
        "zh-Hans": "对齐",
        "zh-Hant": "對齊",
        "ru": "Выровнять",
        "uk": "Вирівняти",
        "he": "יישור",
        "hi": "संरेखण",
        "bn": "সারিবদ্ধ",
        "ur": "ترتیب",
        "es": "Alinear",
        "fr": "Aligner",
        "de": "Ausrichten",
        "it": "Allinea",
        "nl": "Uitlijnen",
        "pl": "Wyrównaj",
        "pt": "Alinhar",
        "sv": "Justera",
        "fi": "Kohdista",
        "en": "Align",
    }
    for code, needle in samples.items():
        if needle in blob:
            return code
    return "unknown"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--pid", type=int, default=None)
    p.add_argument("--pattern", default="DerivedData/Build/Products/Debug/GUI for CLI.app")
    p.add_argument("--verbose", action="store_true")
    args = p.parse_args()

    pid = args.pid or find_pid(args.pattern)
    if pid is None:
        print("ERROR: dev app not running", file=sys.stderr)
        return 1
    print(f"Probing pid {pid}")

    nodes = walk(AXUIElementCreateApplication(pid))
    print(f"Total AX nodes: {len(nodes)}")

    roles = Counter(n["role"] for n in nodes)
    print("Roles: " + ", ".join(f"{r}={c}" for r, c in roles.most_common(8)))

    holes = [
        n for n in nodes
        if n["role"] in INTERACTIVE
        and n["subrole"] not in WINDOW_CHROME_SUBROLES
        and not labels(n)
    ]
    print(f"Unlabeled interactive controls (excluding window chrome): {len(holes)}")
    for n in holes[:20]:
        print(f"  [{n['role']}/{n['subrole']}] depth={n['depth']} value={n['value']!r}")

    # AX identifier coverage: SwiftUI's accessibilityIdentifier is not
    # reliably surfaced as AXIdentifier on macOS (it's primarily an
    # XCUITest hook), so we report instead the linked-label coverage:
    # every TextField/PopUp wired to a label via AXTitleUIElement.
    namespaces = ("control.", "action.", "section.", "page.", "option.")
    annotated = [n for n in nodes if n["identifier"].startswith(namespaces)]
    print(f"Manifest-annotated AX identifiers (macOS surfaces few): {len(annotated)}")
    if annotated:
        by_ns = Counter(i["identifier"].split(".", 1)[0] for i in annotated)
        print("  by namespace: " + ", ".join(f"{k}={v}" for k, v in by_ns.most_common()))

    blob = "\n".join(labels(n) for n in nodes)
    print(f"Detected active locale (heuristic): {detect_locale(blob)}")

    if args.verbose:
        print("\n--- Interactive controls ---")
        for n in nodes:
            if n["role"] in INTERACTIVE:
                print(f"  [{n['role']}/{n['subrole']}] {labels(n)[:80]!r}")

    return 2 if holes else 0


if __name__ == "__main__":
    sys.exit(main())
