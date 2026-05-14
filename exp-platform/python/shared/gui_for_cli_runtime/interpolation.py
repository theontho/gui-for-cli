from __future__ import annotations

import ast
import re
import shlex
from dataclasses import dataclass
from pathlib import PurePath
from typing import Any, Iterable

PLACEHOLDER_PATTERN = re.compile(r"\{\{([^}]+)\}\}")


@dataclass(frozen=True)
class CommandContext:
    field_values: dict[str, Any]
    checked_options: dict[str, Any]
    config_values: dict[str, Any]
    row_values: dict[str, Any]
    bundle_root_path: str
    bundle_workspace_path: str
    home_path: str | None = None
    file_state_values: dict[str, Any] | None = None


def context_value(context: CommandContext, placeholder: str) -> Any:
    if placeholder == "bundleRoot":
        return context.bundle_root_path
    if placeholder == "bundleWorkspace":
        return context.bundle_workspace_path
    if placeholder == "home":
        return context.home_path
    if placeholder.startswith("row."):
        return context.row_values.get(placeholder[4:])
    if placeholder.startswith("config."):
        return context.config_values.get(placeholder[7:])
    computed = computed_file_state_value(context, placeholder)
    if computed is not None:
        return computed
    if placeholder in context.row_values:
        return context.row_values[placeholder]
    if placeholder in context.checked_options:
        return checked_options_value(context.checked_options[placeholder])
    if placeholder in context.field_values:
        return context.field_values[placeholder]
    return context.config_values.get(placeholder)


def interpolate(value: Any, context: CommandContext) -> str:
    return PLACEHOLDER_PATTERN.sub(lambda m: str(context_value(context, m.group(1).strip()) or ""), str(value or ""))


def placeholders_in(values: Iterable[Any]) -> list[str]:
    found: list[str] = []
    for value in values:
        for match in PLACEHOLDER_PATTERN.finditer(str(value or "")):
            placeholder = match.group(1).strip()
            if placeholder not in found:
                found.append(placeholder)
    return found


def missing_placeholders(command: dict[str, Any], context: CommandContext) -> list[str]:
    values = [command.get("executable"), *(command.get("arguments") or [])]
    return missing_required_placeholders(values, context)


def rendered_command(command: dict[str, Any], context: CommandContext) -> dict[str, Any]:
    optional: list[str] = []
    for group in command.get("optionalArguments") or []:
        if not missing_required_placeholders(group, context):
            optional.extend(interpolate(item, context) for item in group)
    return {
        "executable": interpolate(command.get("executable"), context),
        "arguments": [interpolate(item, context) for item in command.get("arguments") or []] + optional,
    }


def display_command(command: dict[str, Any], context: CommandContext) -> str:
    rendered = rendered_command(command, context)
    return " ".join(shell_quote(item) for item in [rendered["executable"], *rendered["arguments"]])


def shell_quote(value: Any) -> str:
    text = str(value or "")
    return text if re.fullmatch(r"[A-Za-z0-9_./-]+", text) else shlex.quote(text)


def is_action_visible(action: dict[str, Any], context: CommandContext) -> bool:
    return all(condition_matches(condition, context) for condition in action.get("visibleWhen") or [])


def disabled_reason(action: dict[str, Any], context: CommandContext, fallback: str, placeholder_labels: dict[str, str] | None = None) -> str | None:
    if any(condition_matches(condition, context) for condition in action.get("disabledWhen") or []):
        return interpolate(action.get("disabledTooltip") or fallback, context)
    missing = missing_placeholders(action.get("command") or {}, context)
    if missing:
        labels = placeholder_labels or {}
        return "Required: " + ", ".join(labels.get(placeholder, placeholder) for placeholder in missing)
    return None


def condition_matches(condition: dict[str, Any], context: CommandContext) -> bool:
    value = str(context_value(context, str(condition.get("placeholder") or "")) or "").strip()
    if "exists" in condition and bool(condition["exists"]) != bool(value):
        return False
    if "equals" in condition and value != interpolate(condition["equals"], context):
        return False
    if "notEquals" in condition and value == interpolate(condition["notEquals"], context):
        return False
    if condition.get("in") and value not in [interpolate(item, context) for item in condition.get("in") or []]:
        return False
    if value in [interpolate(item, context) for item in condition.get("notIn") or []]:
        return False
    comparisons = (
        ("lessThan", lambda left, right: left < right),
        ("lessThanOrEqual", lambda left, right: left <= right),
        ("greaterThan", lambda left, right: left > right),
        ("greaterThanOrEqual", lambda left, right: left >= right),
    )
    for key, op in comparisons:
        if key in condition and not compare_numeric(value, interpolate(condition[key], context), op):
            return False
    return True


def row_context(base: CommandContext, row: dict[str, Any]) -> CommandContext:
    row_values = {**(row.get("values") or {}), "id": row.get("id"), "title": row.get("title") or row.get("id")}
    if row.get("status") is not None:
        row_values["status"] = row.get("status")
    return CommandContext(
        field_values=base.field_values,
        checked_options=base.checked_options,
        config_values=base.config_values,
        row_values=row_values,
        bundle_root_path=base.bundle_root_path,
        bundle_workspace_path=base.bundle_workspace_path,
        home_path=base.home_path,
        file_state_values=base.file_state_values,
    )


def checked_options_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (set, list, tuple)):
        return ",".join(sorted(str(item) for item in value if str(item).strip()))
    return str(value)


def missing_required_placeholders(values: Iterable[Any], context: CommandContext) -> list[str]:
    return [placeholder for placeholder in placeholders_in(values) if not str(context_value(context, placeholder) or "").strip()]


def computed_file_state_value(context: CommandContext, placeholder: str) -> str | None:
    if context.file_state_values and placeholder in context.file_state_values:
        return str(context.file_state_values[placeholder])
    if "." not in placeholder:
        return None
    field_id, prop = placeholder.rsplit(".", 1)
    raw_path = context.field_values.get(field_id) or context.config_values.get(field_id)
    if prop == "pathExtension":
        name = PurePath(str(raw_path or "")).name
        return name.rsplit(".", 1)[1].lower() if "." in name else ""
    return None


def compare_numeric(left: str, right: str, op) -> bool:
    left_value = evaluate_numeric(left)
    right_value = evaluate_numeric(right)
    return left_value is not None and right_value is not None and op(left_value, right_value)


def evaluate_numeric(expression: str) -> float | None:
    try:
        node = ast.parse(str(expression), mode="eval")
        value = _eval_node(node.body)
        return float(value)
    except Exception:
        return None


def _eval_node(node: ast.AST) -> float:
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return float(node.value)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
        value = _eval_node(node.operand)
        return value if isinstance(node.op, ast.UAdd) else -value
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub, ast.Mult, ast.Div)):
        left = _eval_node(node.left)
        right = _eval_node(node.right)
        if isinstance(node.op, ast.Add):
            return left + right
        if isinstance(node.op, ast.Sub):
            return left - right
        if isinstance(node.op, ast.Mult):
            return left * right
        return left / right
    raise ValueError("unsupported numeric expression")
