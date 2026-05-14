from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

RTL_LANGUAGES = {"ar", "fa", "he", "ur"}


@dataclass(frozen=True)
class StringTable:
    locale: str
    values: Mapping[str, str]

    def text(self, key_or_text: object) -> str:
        text = str(key_or_text or "")
        if not text:
            return ""
        return str(self.values.get(text, text))

    @property
    def is_rtl(self) -> bool:
        return language_code(self.locale) in RTL_LANGUAGES


def language_code(locale: str) -> str:
    return locale.replace("_", "-").split("-", 1)[0].lower()


def load_strings(bundle_root: Path, locale: str) -> StringTable:
    strings_dir = bundle_root / "strings"
    candidates = [strings_dir / f"strings.{locale}.toml"]
    lang = language_code(locale)
    if lang != locale:
        candidates.append(strings_dir / f"strings.{lang}.toml")
    candidates.append(strings_dir / "strings.toml")
    for candidate in candidates:
        if candidate.is_file():
            with candidate.open("rb") as handle:
                data = tomllib.load(handle)
            flat = flatten_strings(data)
            return StringTable(locale=locale, values=flat)
    return StringTable(locale=locale, values={})


def flatten_strings(data: Mapping[str, object], prefix: str = "") -> dict[str, str]:
    values: dict[str, str] = {}
    for key, value in data.items():
        full_key = f"{prefix}.{key}" if prefix else str(key)
        if isinstance(value, Mapping):
            values.update(flatten_strings(value, full_key))
        elif isinstance(value, (str, int, float, bool)):
            values[full_key] = str(value)
    return values
