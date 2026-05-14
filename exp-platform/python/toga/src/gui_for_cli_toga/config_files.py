from __future__ import annotations

from pathlib import Path
import json
import tomllib


def read_flat_toml(path: Path) -> dict[str, str]:
    with path.open("rb") as handle:
        raw = tomllib.load(handle)
    return {str(key): str(value) for key, value in raw.items() if not isinstance(value, dict)}


def write_flat_toml(path: Path, values: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"{key} = {json.dumps(value)}" for key, value in sorted(values.items())]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
