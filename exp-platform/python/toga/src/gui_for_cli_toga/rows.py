from __future__ import annotations

from typing import Any
import re

from .commands import PLACEHOLDER_PATTERN


def hydrate_rows(control: dict[str, Any]) -> list[dict[str, Any]]:
    if not control.get("items"):
        return control.get("rows", []) or []
    template = control.get("rowTemplate") or {
        "id": "{{id}}",
        "title": "{{name}}",
        "status": "{{status}}",
        "values": {column.get("id"): "{{" + str(column.get("id")) + "}}" for column in control.get("columns", []) or []},
        "tags": [],
    }
    rows = []
    for index, item in enumerate(control.get("items", []) or [], start=1):
        values = {**item, **(item.get("values") or {})}
        fallback_id = str(values.get("id") or f"row-{index}")
        row = {
            "id": _non_empty(_interpolate_item(template.get("id"), values), fallback_id),
            "title": _non_empty(_interpolate_item(template.get("title"), values), str(values.get("title") or "")),
            "status": _non_empty(_interpolate_item(template.get("status"), values), str(values.get("status") or "")),
            "tooltip": _non_empty(_interpolate_item(template.get("tooltip"), values), str(values.get("tooltip") or "")),
            "values": {key: _interpolate_item(value, values) for key, value in (template.get("values") or {}).items()},
            "tags": _merge_tags(_interpolate_tags(template.get("tags", []), values), item.get("tags", [])),
        }
        rows.append(row)
    return rows


def row_context_values(row: dict[str, Any]) -> dict[str, str]:
    values = {str(k): str(v) for k, v in (row.get("values") or {}).items()}
    values["id"] = str(row.get("id") or "")
    if row.get("title"):
        values["title"] = str(row["title"])
    if row.get("status"):
        values["status"] = str(row["status"])
    return values


def _interpolate_item(value: Any, values: dict[str, Any]) -> str:
    def replace(match: re.Match[str]) -> str:
        raw = match.group(1).strip()
        key = raw[5:] if raw.startswith("item.") else raw
        return str(values.get(key, ""))

    return PLACEHOLDER_PATTERN.sub(replace, str(value or ""))


def _interpolate_tags(tags: list[dict[str, Any]], values: dict[str, Any]) -> list[dict[str, Any]]:
    output = []
    for tag in tags or []:
        title = _interpolate_item(tag.get("title"), values).strip()
        if title:
            output.append({**tag, "id": _interpolate_item(tag.get("id"), values), "title": title})
    return output


def _merge_tags(first: list[dict[str, Any]], second: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[tuple[str, str]] = set()
    merged = []
    for tag in [*first, *(second or [])]:
        key = (str(tag.get("id") or ""), str(tag.get("title") or ""))
        if not key[1] or key in seen:
            continue
        seen.add(key)
        merged.append(tag)
    return merged


def _non_empty(value: str, fallback: str) -> str:
    return value if value.strip() else fallback
