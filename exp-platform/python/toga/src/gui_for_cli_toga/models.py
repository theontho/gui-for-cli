from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class LoadedBundle:
    bundle_root: Path
    workspace_root: Path
    resources_root: Path
    manifest_raw: dict[str, Any]
    manifest: dict[str, Any]
    string_table: dict[str, str]
    localization_code: str
    localization_options: list[str]
    layout_direction: str

    @property
    def display_name(self) -> str:
        return str(self.manifest.get("displayName") or self.manifest.get("id") or "GUI for CLI")

    @property
    def pages(self) -> list[dict[str, Any]]:
        pages = self.manifest.get("pages", [])
        return pages if isinstance(pages, list) else []

    @property
    def terminal_text_direction(self) -> str:
        value = str(self.manifest.get("terminalTextDirection") or "ltr").lower()
        return "rtl" if value in {"rtl", "right-to-left", "righttoleft"} else "ltr"
