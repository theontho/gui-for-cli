#!/usr/bin/env python3
"""Point the WGSExtract bundle at another wgsextract-cli release.

Usage: scripts/bump-wgsextract-cli.py v0.4.4

Updates the release tag setup installs, the bundle version that names the
installers, the tests and docs that pin them, and adds a CHANGELOG entry.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TAG_FILE = ROOT / "examples/WGSExtract/scripts/wgsextract-release-tag.txt"
# Files that name the bundled CLI release's version.
PINNED = [
    "docs/distribution.md",
    "examples/WGSExtract/manifest.json",
    "platform/apple/shared/Tests/GUIForCLICoreTests/AppConfigTests.swift",
    "platform/apple/shared/Tests/GUIForCLICoreTests/ManifestDecodingTests.swift",
    "platform/typescript/tests/conformance.test.mjs",
    "tools/packaging/tests/test_embedded_branding.py",
]
CHANGELOG = ROOT / "docs/CHANGELOG.md"
RELEASES = "https://github.com/theontho/wgsextract-cli/releases/tag"


def main(argv: list[str]) -> int:
    if len(argv) != 2 or not re.fullmatch(r"v\d+\.\d+\.\d+", argv[1]):
        print(__doc__, file=sys.stderr)
        return 2
    new_tag = argv[1]
    old_tag = TAG_FILE.read_text().strip()
    if new_tag == old_tag:
        print(f"The bundle already uses {new_tag}.")
        return 0
    old, new = old_tag[1:], new_tag[1:]
    TAG_FILE.write_text(new_tag + "\n")
    # The version alone, not inside another (10.4.3, 0.4.30).
    version = re.compile(rf"(?<![\d.]){re.escape(old)}(?!\.?\d)")
    for name in PINNED:
        path = ROOT / name
        text, count = version.subn(new, path.read_text())
        if not count:
            print(f"{name} doesn't mention {old}; update it by hand.", file=sys.stderr)
            return 1
        path.write_text(text)
    entry = (
        f"- Bump the bundled WGSExtract CLI installer target to `{new_tag}` "
        f"([release notes]({RELEASES}/{new_tag})).\n"
    )
    text = CHANGELOG.read_text()
    marker = "## Unreleased\n\n### Changed\n"
    if marker not in text:
        print("docs/CHANGELOG.md has no Unreleased/Changed section.", file=sys.stderr)
        return 1
    CHANGELOG.write_text(text.replace(marker, marker + entry, 1))
    print(f"Bundle now uses wgsextract-cli {new_tag} (was {old_tag}).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
