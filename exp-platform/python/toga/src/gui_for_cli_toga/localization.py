from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any
import locale as system_locale
import tomllib

RTL_LANGUAGE_CODES = {"ar", "fa", "he", "ur"}


@dataclass(frozen=True)
class Localization:
    code: str
    table: dict[str, str]
    available: list[str]
    layout_direction: str


def detect_locale() -> str:
    code = system_locale.getlocale()[0] or "en"
    return normalize_locale(code)


def normalize_locale(code: str | None) -> str:
    normalized = (code or "en").replace("_", "-").strip()
    return normalized or "en"


def base_language(code: str) -> str:
    return normalize_locale(code).split("-", 1)[0].lower()


def is_rtl(code: str, table: dict[str, str] | None = None) -> bool:
    explicit = (table or {}).get("language.layoutDirection", "").strip().lower()
    if explicit in {"rtl", "right-to-left", "righttoleft"}:
        return True
    if explicit in {"ltr", "left-to-right", "lefttoright"}:
        return False
    return base_language(code) in RTL_LANGUAGE_CODES


def read_toml_strings(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    with path.open("rb") as handle:
        raw = tomllib.load(handle)
    flattened: dict[str, str] = {}
    _flatten_toml(raw, "", flattened)
    return flattened


def available_locales(strings_dir: Path) -> list[str]:
    if not strings_dir.exists():
        return []
    locales = []
    for path in strings_dir.glob("strings.*.toml"):
        parts = path.name.split(".")
        if len(parts) >= 3:
            locales.append(".".join(parts[1:-1]))
    return sorted(set(locales))


def load_localization(
    bundle_root: Path,
    resources_root: Path,
    requested_locale: str | None,
    default_locale: str | None = None,
) -> Localization:
    code = normalize_locale(requested_locale or default_locale or detect_locale())
    bundle_strings = bundle_root / "strings"
    builtin_strings = resources_root / "BuiltinStrings"

    table: dict[str, str] = {}
    table.update(read_toml_strings(builtin_strings / "strings.en.toml"))
    table.update(_read_locale_match(builtin_strings, code))

    bundle_table = _read_locale_match(bundle_strings, code)
    if code == "en" and not bundle_table:
        bundle_table = read_toml_strings(bundle_strings / "strings.en.toml")
    table.update(bundle_table)

    locales = sorted(set(available_locales(builtin_strings)) | set(available_locales(bundle_strings)))
    return Localization(code=code, table=table, available=locales, layout_direction="rtl" if is_rtl(code, table) else "ltr")


def localize_value(value: Any, table: dict[str, str]) -> Any:
    if value is None:
        return None
    if isinstance(value, str):
        return table.get(value, value)
    return value


def localize_manifest(manifest: dict[str, Any], table: dict[str, str]) -> dict[str, Any]:
    localized = _clone(manifest)
    for key in ("displayName", "summary"):
        localized[key] = localize_value(localized.get(key), table)
    setup = localized.setdefault("setup", {})
    for step in setup.get("steps", []) or []:
        step["label"] = localize_value(step.get("label"), table)
    for entry in localized.get("exitCodeReference", []) or []:
        entry["title"] = localize_value(entry.get("title"), table)
        entry["summary"] = localize_value(entry.get("summary"), table)
    localized["pages"] = [_localize_page(page, table) for page in localized.get("pages", [])]
    return localized


def _read_locale_match(strings_dir: Path, code: str) -> dict[str, str]:
    exact = read_toml_strings(strings_dir / f"strings.{code}.toml")
    if exact:
        return exact
    base = base_language(code)
    if base != code:
        return read_toml_strings(strings_dir / f"strings.{base}.toml")
    return {}


def _localize_page(page: dict[str, Any], table: dict[str, str]) -> dict[str, Any]:
    out = _clone(page)
    for key in ("title", "summary", "sidebarGroup"):
        out[key] = localize_value(out.get(key), table)
    out["sections"] = [_localize_section(section, table) for section in out.get("sections", [])]
    return out


def _localize_section(section: dict[str, Any], table: dict[str, str]) -> dict[str, Any]:
    out = _clone(section)
    for key in ("title", "subtitle", "summary"):
        out[key] = localize_value(out.get(key), table)
    out["controls"] = [_localize_control(control, table) for control in out.get("controls", [])]
    out["actions"] = [_localize_action(action, table) for action in out.get("actions", [])]
    return out


def _localize_control(control: dict[str, Any], table: dict[str, str]) -> dict[str, Any]:
    out = _clone(control)
    for key in ("label", "placeholder", "tooltip"):
        out[key] = localize_value(out.get(key), table)
    out["options"] = [_localize_option(option, table) for option in out.get("options", [])]
    out["columns"] = [_localize_column(column, table) for column in out.get("columns", [])]
    out["rows"] = [_localize_row(row, table) for row in out.get("rows", [])]
    out["rowActions"] = [_localize_action(action, table) for action in out.get("rowActions", [])]
    out["settings"] = [_localize_setting(setting, table) for setting in out.get("settings", [])]
    if "rowTemplate" in out:
        out["rowTemplate"] = _localize_row(out["rowTemplate"], table)
    return out


def _localize_option(option: dict[str, Any], table: dict[str, str]) -> dict[str, Any]:
    out = _clone(option)
    for key in ("title", "group"):
        out[key] = localize_value(out.get(key), table)
    return out


def _localize_column(column: dict[str, Any], table: dict[str, str]) -> dict[str, Any]:
    out = _clone(column)
    out["title"] = localize_value(out.get("title"), table)
    return out


def _localize_row(row: dict[str, Any], table: dict[str, str]) -> dict[str, Any]:
    out = _clone(row)
    for key in ("title", "status", "tooltip"):
        out[key] = localize_value(out.get(key), table)
    out["tags"] = [_localize_tag(tag, table) for tag in out.get("tags", [])]
    return out


def _localize_tag(tag: dict[str, Any], table: dict[str, str]) -> dict[str, Any]:
    out = _clone(tag)
    out["title"] = localize_value(out.get("title"), table)
    return out


def _localize_action(action: dict[str, Any], table: dict[str, str]) -> dict[str, Any]:
    out = _clone(action)
    for key in ("title", "tooltip", "disabledTooltip"):
        out[key] = localize_value(out.get(key), table)
    if out.get("confirm"):
        out["confirm"] = _localize_confirmation(out["confirm"], table)
    return out


def _localize_confirmation(confirm: dict[str, Any], table: dict[str, str]) -> dict[str, Any]:
    out = _clone(confirm)
    for key in ("title", "message", "confirmButtonTitle", "cancelButtonTitle", "requiredText", "prompt"):
        out[key] = localize_value(out.get(key), table)
    return out


def _localize_setting(setting: dict[str, Any], table: dict[str, str]) -> dict[str, Any]:
    out = _clone(setting)
    for key in ("label", "placeholder", "tooltip"):
        out[key] = localize_value(out.get(key), table)
    out["options"] = [_localize_option(option, table) for option in out.get("options", [])]
    return out


def _clone(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _clone(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_clone(item) for item in value]
    return value


def _flatten_toml(value: dict[str, Any], prefix: str, output: dict[str, str]) -> None:
    for key, item in value.items():
        full_key = f"{prefix}.{key}" if prefix else str(key)
        if isinstance(item, dict):
            _flatten_toml(item, full_key, output)
        else:
            output[full_key] = str(item)
