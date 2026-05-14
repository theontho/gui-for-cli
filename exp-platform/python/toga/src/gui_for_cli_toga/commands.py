from __future__ import annotations

from pathlib import Path
from typing import Any, Callable
import re
import shlex

PLACEHOLDER_PATTERN = re.compile(r"\{\{([^{}]+)\}\}")


def context_value(context: dict[str, Any], placeholder: str) -> Any:
    if placeholder in {"bundleRoot", "bundleWorkspace"}:
        return context.get("bundleRootPath") if placeholder == "bundleRoot" else context.get("bundleWorkspacePath")
    if placeholder == "home":
        return context.get("homePath")
    if placeholder.startswith("row."):
        return context.get("rowValues", {}).get(placeholder[4:])
    if placeholder.startswith("config."):
        return context.get("configValues", {}).get(placeholder[7:])
    computed = _computed_file_state_value(context, placeholder)
    if computed is not None:
        return computed
    return (
        context.get("rowValues", {}).get(placeholder)
        or context.get("checkedOptions", {}).get(placeholder)
        or context.get("fieldValues", {}).get(placeholder)
        or context.get("configValues", {}).get(placeholder)
    )


def interpolate(value: Any, context: dict[str, Any]) -> str:
    def replace(match: re.Match[str]) -> str:
        placeholder = match.group(1).strip()
        return str(context_value(context, placeholder) or "")

    return PLACEHOLDER_PATTERN.sub(replace, str(value or ""))


def placeholders_in(values: list[Any]) -> list[str]:
    seen: set[str] = set()
    placeholders: list[str] = []
    for value in values:
        for match in PLACEHOLDER_PATTERN.finditer(str(value or "")):
            placeholder = match.group(1).strip()
            if placeholder and placeholder not in seen:
                seen.add(placeholder)
                placeholders.append(placeholder)
    return placeholders


def missing_placeholders(command: dict[str, Any], context: dict[str, Any]) -> list[str]:
    values = [command.get("executable", ""), *(command.get("arguments", []) or [])]
    return [name for name in placeholders_in(values) if not str(context_value(context, name) or "").strip()]


def render_command(command: dict[str, Any], context: dict[str, Any]) -> tuple[str, list[str]]:
    executable = interpolate(command.get("executable", ""), context)
    args = [interpolate(arg, context) for arg in command.get("arguments", []) or []]
    for group in command.get("optionalArguments", []) or []:
        if not _missing_required_placeholders(group, context):
            args.extend(interpolate(arg, context) for arg in group)
    return executable, args


def display_command(rendered: tuple[str, list[str]]) -> str:
    executable, args = rendered
    return " ".join(shlex.quote(part) for part in [executable, *args])


def is_action_visible(action: dict[str, Any], context: dict[str, Any]) -> bool:
    return all(condition_matches(condition, context) for condition in action.get("visibleWhen", []) or [])


def disabled_reason(action: dict[str, Any], context: dict[str, Any], fallback: str = "This action is not available.") -> str | None:
    if any(condition_matches(condition, context) for condition in action.get("disabledWhen", []) or []):
        tooltip = action.get("disabledTooltip")
        return interpolate(tooltip, context) if tooltip else fallback
    return None


def condition_matches(condition: dict[str, Any], context: dict[str, Any]) -> bool:
    value = str(context_value(context, str(condition.get("placeholder") or "")) or "").strip()
    if "exists" in condition and bool(condition["exists"]) != bool(value):
        return False
    if condition.get("equals") is not None and value != interpolate(condition["equals"], context):
        return False
    if condition.get("notEquals") is not None and value == interpolate(condition["notEquals"], context):
        return False
    if condition.get("in") and value not in [interpolate(item, context) for item in condition.get("in", [])]:
        return False
    if condition.get("notIn") and value in [interpolate(item, context) for item in condition.get("notIn", [])]:
        return False
    comparisons: list[tuple[str, Callable[[float, float], bool]]] = [
        ("lessThan", lambda left, right: left < right),
        ("lessThanOrEqual", lambda left, right: left <= right),
        ("greaterThan", lambda left, right: left > right),
        ("greaterThanOrEqual", lambda left, right: left >= right),
    ]
    for key, predicate in comparisons:
        if condition.get(key) is not None and not _compare_numeric(value, interpolate(condition[key], context), predicate):
            return False
    return True


def _missing_required_placeholders(values: list[Any], context: dict[str, Any]) -> list[str]:
    return [name for name in placeholders_in(values) if not str(context_value(context, name) or "").strip()]


def _compare_numeric(left: str, right: str, predicate: Callable[[float, float], bool]) -> bool:
    try:
        return predicate(float(left), float(right))
    except ValueError:
        return False


def _computed_file_state_value(context: dict[str, Any], placeholder: str) -> str | None:
    if placeholder in context.get("fileStateValues", {}):
        return str(context["fileStateValues"][placeholder])
    if "." not in placeholder:
        return None
    field_id, property_name = placeholder.rsplit(".", 1)
    raw_path = context.get("fieldValues", {}).get(field_id) or context.get("configValues", {}).get(field_id)
    if not raw_path:
        return None
    path = Path(str(raw_path))
    if property_name == "pathExtension":
        return path.suffix.lstrip(".")
    if property_name in {"fileSize", "fileSizeGB"}:
        try:
            size = path.stat().st_size
        except (FileNotFoundError, OSError):
            return None
        return str(round(size / 1_000_000_000, 3)) if property_name == "fileSizeGB" else str(size)
    return None
