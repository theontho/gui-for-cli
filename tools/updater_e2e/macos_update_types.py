from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
DEFAULT_REPO = "theontho/gui-for-cli"
OLD_VERSION = "0.0.1"
SPARKLE_NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
DOWNLOAD_TIMEOUT_SECONDS = 120


@dataclass(frozen=True)
class AppMetadata:
    app_name: str
    bundle_id: str
    version: str
    app_path: Path


@dataclass(frozen=True)
class ReleaseMetadata:
    version: str
    appcast_url: str
    latest_json_url: str
    sparkle_public_key: str
    tauri_public_key: str
    swiftui: AppMetadata
    tauri: AppMetadata
