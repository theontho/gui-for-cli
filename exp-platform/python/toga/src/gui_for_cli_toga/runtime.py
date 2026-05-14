from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
import json
import os
import subprocess

from .commands import disabled_reason, display_command, interpolate, is_action_visible, missing_placeholders, render_command
from .config_files import read_flat_toml, write_flat_toml
from .manifest_utils import PERSISTED_FIELD_KINDS, all_actions, all_controls, apply_payload_to_control, config_editor_controls, config_value_key, section_kind
from .models import LoadedBundle


@dataclass
class RenderState:
    field_values: dict[str, str] = field(default_factory=dict)
    checked_options: dict[str, set[str]] = field(default_factory=dict)
    config_values: dict[str, str] = field(default_factory=dict)
    section_values: dict[str, dict[str, str]] = field(default_factory=dict)
    file_state_values: dict[str, str] = field(default_factory=dict)
    selected_page_id: str = ""
    terminal_visible: bool = True
    sidebar_visible: bool = True


@dataclass(frozen=True)
class ActionState:
    visible: bool
    enabled: bool
    reason: str | None
    command_line: str | None
    missing_inputs: list[str]


class RuntimeModel:
    def __init__(self, bundle: LoadedBundle):
        self.bundle = bundle
        self.state = RenderState()
        self.data_errors: dict[str, str] = {}
        self._initialize_state()

    def bootstrap(self) -> None:
        for control in config_editor_controls(self.bundle.manifest):
            self.load_config(control)

    def context(self, row_values: dict[str, Any] | None = None, section_values: dict[str, Any] | None = None) -> dict[str, Any]:
        row_values = row_values or {}
        section_values = section_values or {}
        return {
            "fieldValues": {**self.state.field_values, **section_values},
            "checkedOptions": {key: ",".join(sorted(value)) for key, value in self.state.checked_options.items()},
            "configValues": {**self.state.config_values, **self.state.field_values, **section_values},
            "rowValues": row_values,
            "fileStateValues": self.state.file_state_values,
            "bundleRootPath": str(self.bundle.bundle_root),
            "bundleWorkspacePath": str(self.bundle.workspace_root),
            "homePath": str(Path.home()),
        }

    def render_snapshot(self) -> dict[str, Any]:
        pages = []
        for page in self.bundle.pages:
            sections = []
            for section in page.get("sections", []) or []:
                controls = section.get("controls", []) or []
                actions = section.get("actions", []) or []
                sections.append({
                    "id": section.get("id"),
                    "title": section.get("title"),
                    "kind": section_kind(section),
                    "controls": [control.get("kind", "unknown") for control in controls],
                    "actions": [action.get("id") for action in actions],
                })
            pages.append({"id": page.get("id"), "title": page.get("title"), "sections": sections})
        controls = all_controls(self.bundle.manifest)
        actions = all_actions(self.bundle.manifest)
        return {
            "display_name": self.bundle.display_name,
            "pages": pages,
            "page_count": len(pages),
            "control_count": len(controls),
            "action_count": len(actions),
            "setup_steps": len((self.bundle.manifest.get("setup") or {}).get("steps", []) or []),
            "terminal_text_direction": self.bundle.terminal_text_direction,
            "layout_direction": self.bundle.layout_direction,
            "path_fields_ltr": True,
            "terminal_ltr": self.bundle.terminal_text_direction == "ltr",
            "control_kinds": sorted({control.get("kind", "unknown") for control in controls}),
        }

    def action_state(self, action: dict[str, Any], row_values: dict[str, Any] | None = None) -> ActionState:
        context = self.context(row_values)
        if not is_action_visible(action, context):
            return ActionState(False, False, "hidden", None, [])
        disabled = disabled_reason(action, context)
        if disabled:
            return ActionState(True, False, disabled, None, [])
        command = action.get("command") or {}
        missing = missing_placeholders(command, context)
        if missing:
            return ActionState(True, False, f"Missing: {', '.join(missing)}", None, missing)
        rendered = render_command(command, context)
        return ActionState(True, True, None, display_command(rendered), [])

    def refresh_data_sources_for_page(self, page_id: str) -> None:
        for page in self.bundle.pages:
            if page.get("id") != page_id:
                continue
            self._refresh_page(page)

    def refresh_all_data_sources(self) -> None:
        for page in self.bundle.pages:
            self._refresh_page(page)

    def run_data_source(self, data_source: dict[str, Any], row_values: dict[str, Any] | None = None) -> dict[str, Any]:
        script = str(data_source.get("path") or "").strip()
        if not script:
            raise ValueError("missing data source path")
        executable = self.resolve_bundle_path(script)
        context = self.context(row_values)
        args = [interpolate(str(arg), context) for arg in data_source.get("arguments", []) or []]
        cwd = self.bundle.bundle_root
        if data_source.get("workingDirectory"):
            cwd = Path(self.resolve_bundle_path(str(data_source["workingDirectory"])))
        env = os.environ.copy()
        for key, value in (data_source.get("environment") or {}).items():
            env[key] = interpolate(str(value), context)
        result = subprocess.run(
            [executable, *args],
            cwd=cwd,
            env=env,
            text=True,
            capture_output=True,
            timeout=15,
            check=False,
        )
        if result.returncode != 0:
            detail = result.stderr.strip() or result.stdout.strip()
            raise RuntimeError(f"data source {script} exited {result.returncode}: {detail}")
        payload = json.loads(result.stdout or "{}")
        if not isinstance(payload, dict):
            raise ValueError(f"data source {script} did not return an object")
        return payload

    def load_config(self, control: dict[str, Any]) -> None:
        config_file = control.get("configFile") or {}
        raw_path = str(config_file.get("path") or "").strip()
        if not raw_path:
            return
        path = Path(self.resolve_path_tokens(raw_path))
        bootstrap = config_file.get("bootstrap") or {}
        if bootstrap.get("mode") == "createIfMissing" and not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("", encoding="utf-8")
        values = read_flat_toml(path) if path.exists() else {}
        for setting in control.get("settings", []) or []:
            key = str(setting.get("key") or setting.get("id") or "")
            setting_id = str(setting.get("id") or key)
            value = str(values.get(key, setting.get("value", "")))
            config_key = config_value_key(control, setting)
            self.state.config_values[config_key] = value
            if setting_id:
                self.state.field_values[setting_id] = value

    def save_config(self, control: dict[str, Any]) -> None:
        config_file = control.get("configFile") or {}
        raw_path = str(config_file.get("path") or "").strip()
        if not raw_path:
            return
        path = Path(self.resolve_path_tokens(raw_path))
        values = {}
        for setting in control.get("settings", []) or []:
            key = str(setting.get("key") or setting.get("id") or "")
            setting_id = str(setting.get("id") or key)
            if setting_id in self.state.field_values:
                values[key] = self.state.field_values[setting_id]
            elif key in self.state.field_values:
                values[key] = self.state.field_values[key]
            else:
                values[key] = self.state.config_values.get(config_value_key(control, setting), "")
        write_flat_toml(path, values)

    def resolve_bundle_path(self, value: str) -> str:
        resolved = self.resolve_path_tokens(value)
        path = Path(resolved)
        if path.is_absolute():
            return str(path)
        return str(self.bundle.bundle_root / path)

    def resolve_path_tokens(self, value: str) -> str:
        return (
            str(value)
            .replace("{{bundleRoot}}", str(self.bundle.bundle_root))
            .replace("{{bundleWorkspace}}", str(self.bundle.workspace_root))
            .replace("{{bundleRootBasename}}", self.bundle.bundle_root.name)
            .replace("{{home}}", str(Path.home()))
        )

    def _initialize_state(self) -> None:
        pages = self.bundle.pages
        self.state.selected_page_id = str(pages[0].get("id") if pages else "")
        for control in all_controls(self.bundle.manifest):
            control_id = str(control.get("id") or "")
            if control.get("kind") in PERSISTED_FIELD_KINDS and control_id:
                self.state.field_values[control_id] = str(control.get("value", self.state.field_values.get(control_id, "")))
            if control.get("kind") == "checkboxGroup" and control_id:
                selected = {str(option.get("id")) for option in control.get("options", []) or [] if option.get("selected")}
                self.state.checked_options[control_id] = selected
        for control in config_editor_controls(self.bundle.manifest):
            for setting in control.get("settings", []) or []:
                self.state.config_values[config_value_key(control, setting)] = str(setting.get("value", ""))

    def _refresh_page(self, page: dict[str, Any]) -> None:
        for section in page.get("sections", []) or []:
            if section.get("dataSource"):
                self._apply_section_payload(section, self.run_data_source(section["dataSource"]))
            for control in section.get("controls", []) or []:
                if control.get("dataSource"):
                    payload = self.run_data_source(control["dataSource"])
                    apply_payload_to_control(control, payload)
                for setting in control.get("settings", []) or []:
                    if setting.get("dataSource"):
                        payload = self.run_data_source(setting["dataSource"])
                        if payload.get("options"):
                            setting["options"] = payload["options"]

    def _apply_section_payload(self, section: dict[str, Any], payload: dict[str, Any]) -> None:
        if payload.get("values"):
            self.state.section_values[str(section.get("id"))] = {str(k): str(v) for k, v in payload["values"].items()}
            self.state.field_values.update({str(k): str(v) for k, v in payload["values"].items()})
        if payload.get("actions"):
            section["actions"] = payload["actions"]
