from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def parse_flat_toml(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"Invalid config line {line_no}: missing '='")
        key, value = line.split("=", 1)
        parsed_key = _parse_scalar(key.strip(), line_no)
        if not parsed_key:
            raise ValueError(f"Invalid config line {line_no}: empty key")
        values[parsed_key] = _parse_scalar(value.strip(), line_no)
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
    tmp_path = path.with_suffix(f"{path.suffix}.tmp")
    tmp_path.write_text(serialize_flat_toml(values), encoding="utf-8")
    tmp_path.replace(path)


def _parse_scalar(value: str, line_no: int | None = None) -> str:
    if value.startswith('"'):
        try:
            return str(json.loads(value))
        except json.JSONDecodeError as error:
            where = f" on line {line_no}" if line_no is not None else ""
            raise ValueError(f"Invalid quoted scalar{where}: {value!r}") from error
    return value
