from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def parse_flat_toml(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[_parse_scalar(key.strip())] = _parse_scalar(value.strip())
    return values


def serialize_flat_toml(values: dict[str, Any]) -> str:
    lines = []
    for key, value in sorted(values.items()):
        encoded_key = key if key.replace("_", "").replace("-", "").isalnum() else json.dumps(key)
        lines.append(f"{encoded_key} = {json.dumps(str(value))}")
    return "\n".join(lines) + "\n"


def load_config_values(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    return parse_flat_toml(path.read_text(encoding="utf-8"))


def save_config_values(path: Path, values: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(serialize_flat_toml(values), encoding="utf-8")


def _parse_scalar(value: str) -> str:
    if value.startswith('"'):
        try:
            return str(json.loads(value))
        except json.JSONDecodeError:
            return value.strip('"')
    return value
