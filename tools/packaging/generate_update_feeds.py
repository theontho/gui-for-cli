#!/usr/bin/env python3
"""Generate GitHub Release-backed update metadata for desktop packages."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import xml.sax.saxutils
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, help="GitHub repository in owner/name form")
    parser.add_argument("--tag", required=True, help="GitHub release tag")
    parser.add_argument("--version", required=True, help="SemVer app version")
    parser.add_argument("--artifacts-root", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--release-base-url", default="")
    args = parser.parse_args()

    artifacts = collect_artifacts(args.artifacts_root)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    base_url = args.release_base_url or f"https://github.com/{args.repo}/releases/download/{args.tag}"

    wrote = False
    if write_tauri_latest_json(args.output_dir / "latest.json", artifacts, args.version, base_url):
        wrote = True
    if write_sparkle_appcast(args.output_dir / "appcast.xml", artifacts, args.version, base_url):
        wrote = True

    if not wrote:
        print("No signed updater feeds were generated; signed updater artifacts were not found.", file=sys.stderr)
    return 0


def collect_artifacts(root: Path) -> dict[str, Path]:
    return {path.name: path for path in root.rglob("*") if path.is_file()}


def write_tauri_latest_json(
    output_path: Path,
    artifacts: dict[str, Path],
    version: str,
    base_url: str,
) -> bool:
    platforms: dict[str, dict[str, str]] = {}
    add_tauri_platform(platforms, artifacts, "windows-x86_64", [r".*-setup\.exe$"], base_url)
    add_tauri_platform(platforms, artifacts, "darwin-x86_64", [r".*\.app\.tar\.gz$"], base_url)
    add_tauri_platform(platforms, artifacts, "darwin-aarch64", [r".*\.app\.tar\.gz$"], base_url)
    add_tauri_platform(platforms, artifacts, "linux-x86_64", [r".*\.AppImage$"], base_url)

    if not platforms:
        return False

    payload = {
        "version": version,
        "notes": f"GUI for CLI {version}",
        "pub_date": datetime.now(timezone.utc).isoformat(),
        "platforms": platforms,
    }
    output_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return True


def add_tauri_platform(
    platforms: dict[str, dict[str, str]],
    artifacts: dict[str, Path],
    platform: str,
    patterns: list[str],
    base_url: str,
) -> None:
    artifact = first_matching_artifact(artifacts, patterns)
    if artifact is None:
        return
    signature_path = artifacts.get(f"{artifact.name}.sig")
    if signature_path is None:
        return
    signature = signature_path.read_text(encoding="utf-8").strip()
    if not signature:
        return
    platforms[platform] = {
        "signature": signature,
        "url": f"{base_url}/{url_escape_path(artifact.name)}",
    }


def first_matching_artifact(artifacts: dict[str, Path], patterns: list[str]) -> Path | None:
    for pattern in patterns:
        regex = re.compile(pattern)
        matches = sorted(path for name, path in artifacts.items() if regex.fullmatch(name))
        if matches:
            return matches[0]
    return None


def write_sparkle_appcast(
    output_path: Path,
    artifacts: dict[str, Path],
    version: str,
    base_url: str,
) -> bool:
    dmg = first_matching_artifact(artifacts, [r".*\.dmg$"])
    if dmg is None:
        return False
    signature_fragment = sparkle_signature_fragment(dmg, artifacts)
    if not signature_fragment:
        return False

    now = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S %z")
    title = xml_escape(f"Version {version}")
    download_url = xml_escape(f"{base_url}/{url_escape_path(dmg.name)}")
    appcast = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>GUI for CLI Updates</title>
    <item>
      <title>{title}</title>
      <sparkle:version>{xml_escape(version)}</sparkle:version>
      <sparkle:shortVersionString>{xml_escape(version)}</sparkle:shortVersionString>
      <pubDate>{now}</pubDate>
      <enclosure url="{download_url}" {signature_fragment} type="application/octet-stream" />
    </item>
  </channel>
</rss>
"""
    output_path.write_text(appcast, encoding="utf-8")
    return True


def sparkle_signature_fragment(dmg: Path, artifacts: dict[str, Path]) -> str:
    sidecar = artifacts.get(f"{dmg.name}.sparkle-signature")
    if sidecar is not None:
        return normalize_sparkle_fragment(sidecar.read_text(encoding="utf-8"))

    sign_update = os.environ.get("SPARKLE_SIGN_UPDATE")
    if not sign_update:
        return ""
    result = subprocess.run([sign_update, str(dmg)], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        return ""
    return normalize_sparkle_fragment(result.stdout)


def normalize_sparkle_fragment(text: str) -> str:
    ed_signature = re.search(r'sparkle:edSignature="[^"]+"', text)
    length = re.search(r'(?:sparkle:)?length="\d+"', text)
    if not ed_signature or not length:
        return ""
    return f"{ed_signature.group(0)} {length.group(0).replace('sparkle:length', 'length')}"


def url_escape_path(value: str) -> str:
    from urllib.parse import quote

    return quote(value)


def xml_escape(value: str) -> str:
    return xml.sax.saxutils.escape(value)


if __name__ == "__main__":
    raise SystemExit(main())
