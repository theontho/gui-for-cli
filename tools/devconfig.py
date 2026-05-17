from __future__ import annotations

import os
import tomllib
from functools import lru_cache
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
DEVCONFIG_PATH = REPO_ROOT / ".devconfig.toml"


@lru_cache(maxsize=1)
def load_devconfig() -> dict[str, Any]:
    if not DEVCONFIG_PATH.exists():
        return {}
    with DEVCONFIG_PATH.open("rb") as handle:
        return tomllib.load(handle)



def reload_devconfig() -> dict[str, Any]:
    load_devconfig.cache_clear()
    return load_devconfig()



def get_path(*keys: str, default: Any = None) -> Any:
    current: Any = load_devconfig()
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            return default
        current = current[key]
    return current



def env_or_config(env_name: str, *config_path: str, default: str = "") -> str:
    value = os.environ.get(env_name)
    if value:
        return value
    config_value = get_path(*config_path, default=default)
    return config_value if isinstance(config_value, str) else default
