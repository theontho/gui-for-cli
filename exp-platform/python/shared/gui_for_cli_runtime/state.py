from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Any

from .bundle import Bundle
from .interpolation import (
    CommandContext,
    disabled_reason,
    display_command,
    is_action_visible,
    row_context,
)

PERSISTED_CONTROL_KINDS = {"text", "path", "dropdown", "toggle"}


@dataclass
class RuntimeState:
    field_values: dict[str, Any]
    checked_options: dict[str, set[str]]
    config_values: dict[str, Any]
    data_source_payloads: dict[str, dict[str, Any]] = field(default_factory=dict)
    data_source_errors: dict[str, str] = field(default_factory=dict)
    selected_page_id: str | None = None

    @classmethod
    def for_bundle(cls, bundle: Bundle) -> "RuntimeState":
        manifest = bundle.manifest
        pages = manifest.get("pages") or []
        selected_page_id = pages[0].get("id") if pages else None
        return cls(
            field_values=initial_field_values(manifest),
            checked_options=initial_checked_options(manifest),
            config_values=initial_config_values(manifest),
            selected_page_id=selected_page_id,
        )

    def context(self, bundle: Bundle, row_values: dict[str, Any] | None = None, section_values: dict[str, Any] | None = None) -> CommandContext:
        fields = {**self.field_values, **(section_values or {})}
        configs = {**self.config_values, **self.field_values, **(section_values or {})}
        return CommandContext(
            field_values=fields,
            checked_options=self.checked_options,
            config_values=configs,
            row_values=row_values or {},
            bundle_root_path=str(bundle.bundle_root),
            bundle_workspace_path=str(bundle.workspace_root),
            home_path=os.path.expanduser("~"),
        )


@dataclass(frozen=True)
class ActionRenderState:
    id: str
    title: str
    visible: bool
    disabled_reason: str | None
    command_display: str
    action: dict[str, Any]

    @property
    def enabled(self) -> bool:
        return self.visible and self.disabled_reason is None


@dataclass(frozen=True)
class CoreRenderState:
    pages: list[dict[str, Any]]
    action_states: dict[str, ActionRenderState]
    row_action_states: dict[str, list[ActionRenderState]]
    control_count: int
    action_count: int
    rtl_layout: bool
    terminal_text_direction: str


def build_core_state(bundle: Bundle, state: RuntimeState) -> CoreRenderState:
    action_states: dict[str, ActionRenderState] = {}
    row_action_states: dict[str, list[ActionRenderState]] = {}
    pages: list[dict[str, Any]] = []
    control_count = 0
    action_count = 0
    base_context = state.context(bundle)
    for page in bundle.manifest.get("pages") or []:
        rendered_sections = []
        for section in page.get("sections") or []:
            section_values = state.data_source_payloads.get(f"section:{section.get('id')}", {}).get("values") or {}
            section_context = state.context(bundle, section_values=section_values)
            rendered_controls = []
            for control in section.get("controls") or []:
                control_count += 1
                rendered_control = hydrated_control(control, state.data_source_payloads.get(f"control:{control.get('id')}"))
                rendered_controls.append(rendered_control)
                for row in hydrated_rows(rendered_control):
                    states = []
                    for row_action in rendered_control.get("rowActions") or []:
                        action_count += 1
                        states.append(render_action(bundle, row_action, row_context(base_context, row)))
                    if states:
                        row_action_states[f"{control.get('id')}:{row.get('id')}"] = states
            rendered_actions = []
            for action in section.get("actions") or []:
                action_count += 1
                rendered = render_action(bundle, action, section_context)
                action_states[action_key(section, action)] = rendered
                rendered_actions.append(rendered)
            rendered_sections.append({**section, "controls": rendered_controls, "actionStates": rendered_actions})
        pages.append({**page, "sections": rendered_sections})
    return CoreRenderState(
        pages=pages,
        action_states=action_states,
        row_action_states=row_action_states,
        control_count=control_count,
        action_count=action_count,
        rtl_layout=bundle.rtl_layout,
        terminal_text_direction=bundle.terminal_text_direction,
    )


def render_action(bundle: Bundle, action: dict[str, Any], context: CommandContext) -> ActionRenderState:
    visible = is_action_visible(action, context)
    fallback = "This action is not available."
    reason = disabled_reason(action, context, fallback, placeholder_labels(bundle))
    command = action.get("command") or {}
    return ActionRenderState(
        id=str(action.get("id") or "action"),
        title=bundle.strings.text(action.get("title") or action.get("id") or "action"),
        visible=visible,
        disabled_reason=reason,
        command_display=display_command(command, context) if command else "",
        action=action,
    )


def initial_field_values(manifest: dict[str, Any]) -> dict[str, Any]:
    values: dict[str, Any] = {}
    for control in all_controls(manifest):
        if control.get("kind") in PERSISTED_CONTROL_KINDS:
            control_id = str(control.get("id"))
            values[control_id] = control.get("value", default_control_value(control, values.get(control_id, "")))
    return values


def initial_checked_options(manifest: dict[str, Any]) -> dict[str, set[str]]:
    values: dict[str, set[str]] = {}
    for control in all_controls(manifest):
        if control.get("kind") == "checkboxGroup":
            selected = {str(option.get("id")) for option in control.get("options") or [] if option.get("selected")}
            values[str(control.get("id"))] = selected
    return values


def initial_config_values(manifest: dict[str, Any]) -> dict[str, Any]:
    values: dict[str, Any] = {}
    for control in all_controls(manifest):
        if control.get("kind") == "configEditor":
            for setting in control.get("settings") or []:
                values[f"{control.get('id')}.{setting.get('id')}"] = setting.get("value", "")
                if setting.get("id") not in values:
                    values[str(setting.get("id"))] = setting.get("value", "")
    return values


def all_controls(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    controls: list[dict[str, Any]] = []
    for page in manifest.get("pages") or []:
        for section in page.get("sections") or []:
            controls.extend(section.get("controls") or [])
    return controls


def default_control_value(control: dict[str, Any], fallback: Any = "") -> Any:
    if control.get("kind") == "dropdown":
        options = control.get("options") or []
        selected = next((option for option in options if option.get("selected")), None)
        if selected:
            return selected.get("id", fallback)
        if options:
            return options[0].get("id", fallback)
    return fallback


def placeholder_labels(bundle: Bundle) -> dict[str, str]:
    labels: dict[str, str] = {}
    for control in all_controls(bundle.manifest):
        control_id = str(control.get("id") or "")
        if control_id:
            labels[control_id] = bundle.strings.text(control.get("label") or control_id)
        if control.get("kind") == "configEditor":
            for setting in control.get("settings") or []:
                setting_id = str(setting.get("id") or "")
                if not setting_id:
                    continue
                label = bundle.strings.text(setting.get("label") or setting_id)
                labels[setting_id] = label
                labels[f"{control_id}.{setting_id}"] = label
    return labels


def action_key(section: dict[str, Any], action: dict[str, Any]) -> str:
    return f"{section.get('id')}:{action.get('id')}"


def hydrated_control(control: dict[str, Any], payload: dict[str, Any] | None) -> dict[str, Any]:
    if not payload:
        return control
    next_control = {**control}
    if "options" in payload:
        next_control["options"] = payload["options"]
    if "rows" in payload:
        next_control["rows"] = payload["rows"]
        next_control["items"] = []
    if "items" in payload:
        next_control["items"] = payload["items"]
    if "rowActions" in payload or "actions" in payload:
        next_control["rowActions"] = payload.get("rowActions") or payload.get("actions")
    return next_control


def hydrated_rows(control: dict[str, Any]) -> list[dict[str, Any]]:
    items = control.get("items") or []
    if not items:
        return list(control.get("rows") or [])
    template = control.get("rowTemplate") or {
        "id": "{{id}}",
        "title": "{{name}}",
        "values": {column.get("id"): "{{" + str(column.get("id")) + "}}" for column in control.get("columns") or []},
        "status": "{{status}}",
        "tags": [],
    }
    return [hydrate_row(template, item, index) for index, item in enumerate(items)]


def hydrate_row(template: dict[str, Any], item: dict[str, Any], index: int) -> dict[str, Any]:
    values = {**item, **(item.get("values") or {})}
    fallback_id = str(values.get("id") or f"row-{index + 1}")
    row_id = non_empty(interpolate_item(template.get("id"), values)) or fallback_id
    row = {
        "id": row_id,
        "title": non_empty(interpolate_item(template.get("title"), values)) or item.get("title"),
        "status": non_empty(interpolate_item(template.get("status"), values)) or item.get("status"),
        "values": {key: interpolate_item(value, values) for key, value in (template.get("values") or {}).items()},
        "tags": merge_tags([hydrate_tag(tag, values) for tag in template.get("tags") or []], item.get("tags") or []),
    }
    tooltip = non_empty(interpolate_item(template.get("tooltip"), values)) or item.get("tooltip")
    if tooltip:
        row["tooltip"] = tooltip
    return row


def hydrate_tag(tag: dict[str, Any], values: dict[str, Any]) -> dict[str, Any]:
    return {**tag, "id": interpolate_item(tag.get("id"), values), "title": interpolate_item(tag.get("title"), values)}


def merge_tags(first: list[dict[str, Any]], second: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[tuple[str, str]] = set()
    merged: list[dict[str, Any]] = []
    for tag in [*first, *second]:
        title = str(tag.get("title") or "").strip()
        key = (str(tag.get("id") or ""), title)
        if title and key not in seen:
            seen.add(key)
            merged.append(tag)
    return merged


def interpolate_item(value: Any, values: dict[str, Any]) -> str:
    from .interpolation import PLACEHOLDER_PATTERN

    def replace(match):
        raw = match.group(1).strip()
        key = raw[5:] if raw.startswith("item.") else raw
        return str(values.get(key) or "")

    return PLACEHOLDER_PATTERN.sub(replace, str(value or ""))


def non_empty(value: Any) -> str | None:
    text = str(value or "").strip()
    return text or None
