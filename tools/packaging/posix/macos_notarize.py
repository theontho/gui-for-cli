"""Notarize and staple macOS DMGs.

Tauri notarizes and staples the .app it builds but only signs the DMG, so Gatekeeper rejects a
downloaded DMG as an "Unnotarized Developer ID". This submits each DMG with the same credentials
Tauri reads (an App Store Connect API key, or an Apple ID) and staples the ticket to it.
"""

from __future__ import annotations

import os
from collections.abc import Mapping
from pathlib import Path

from common import run


def notarytool_credentials(env: Mapping[str, str]) -> list[str] | None:
    """notarytool's credential arguments from Tauri's notarization variables, or None if unset."""
    api_key = env.get("APPLE_API_KEY")
    api_issuer = env.get("APPLE_API_ISSUER")
    api_key_path = env.get("APPLE_API_KEY_PATH")
    if api_key and api_issuer and api_key_path:
        return ["--key", api_key_path, "--key-id", api_key, "--issuer", api_issuer]
    apple_id = env.get("APPLE_ID")
    password = env.get("APPLE_PASSWORD")
    team_id = env.get("APPLE_TEAM_ID")
    if apple_id and password and team_id:
        return ["--apple-id", apple_id, "--password", password, "--team-id", team_id]
    return None


def notarize_dmgs(dmgs: list[Path], env: Mapping[str, str] = os.environ) -> None:
    credentials = notarytool_credentials(env)
    if credentials is None:
        if env.get("PACKAGE_REQUIRE_MACOS_SIGNING"):
            raise SystemExit("Release DMGs must be notarized, but no notarization credentials are set.")
        print("Notarization credentials are not set; leaving the DMG unnotarized.")
        return
    for dmg in dmgs:
        run(["xcrun", "notarytool", "submit", str(dmg), *credentials, "--wait"])
        run(["xcrun", "stapler", "staple", str(dmg)])
