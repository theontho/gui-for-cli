from __future__ import annotations

from typing import Any

PERSISTED_FIELD_KINDS = {"text", "path", "dropdown", "toggle"}


def all_controls(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    controls: list[dict[str, Any]] = []
    for page in manifest.get("pages", []) or []:
        for section in page.get("sections", []) or []:
            controls.extend(section.get("controls", []) or [])
    return controls


def all_actions(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []
    for page in manifest.get("pages", []) or []:
        for section in page.get("sections", []) or []:
            actions.extend(section.get("actions", []) or [])
            for control in section.get("controls", []) or []:
                actions.extend(control.get("rowActions", []) or [])
    return actions


def config_editor_controls(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    return [control for control in all_controls(manifest) if control.get("kind") == "configEditor"]


def config_value_key(control: dict[str, Any], setting: dict[str, Any]) -> str:
    return f"{control.get('id')}.{setting.get('id')}"


def apply_payload_to_control(control: dict[str, Any], payload: dict[str, Any]) -> None:
    for key in ("options", "rows", "items", "rowActions"):
        if payload.get(key):
            control[key] = payload[key]
    if payload.get("actions") and not payload.get("rowActions"):
        control["rowActions"] = payload["actions"]


def section_kind(section: dict[str, Any]) -> str:
    control_kinds = {control.get("kind") for control in section.get("controls", []) or []}
    if "configEditor" in control_kinds:
        return "settings"
    if "libraryList" in control_kinds:
        return "library"
    if section.get("actions"):
        return "actions"
    return "setup" if section.get("id") == "setup" else "controls"
