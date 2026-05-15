from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import os
import time
import uuid

import toga
from toga.style import Pack
from toga.style.pack import COLUMN, ROW

from ..process_runner import ProcessRunner
from ..commands import display_command, render_command
from ..rows import hydrate_rows, row_context_values
from ..runtime import RuntimeModel


@dataclass
class TerminalTab:
    identifier: str
    title: str
    output: toga.MultilineTextInput
    running: bool = False


class GUIForCLITogaApp(toga.App):
    def __init__(self, model: RuntimeModel, *, benchmark_started: float | None = None, benchmark_output: Path | None = None):
        self.model = model
        self.benchmark_started = benchmark_started
        self.benchmark_output = benchmark_output
        self.runner = ProcessRunner()
        self.terminal_tabs: dict[str, TerminalTab] = {}
        self.page_content: toga.Box | None = None
        self.terminal_box: toga.Box | None = None
        self.status_label: toga.Label | None = None
        super().__init__(formal_name=f"{model.bundle.display_name} (Toga)", app_id="dev.guiforcli.toga")

    def startup(self) -> None:
        self.main_window = toga.MainWindow(title=self.formal_name)
        self.main_window.content = self._build_shell()
        self.main_window.on_close = self._on_close
        self.main_window.show()
        if self.benchmark_started is not None:
            self._emit_benchmark()

    def _build_shell(self) -> toga.Box:
        top = self._top_bar()
        nav = self._sidebar()
        self.page_content = toga.Box(style=Pack(direction=COLUMN, flex=1, padding=10))
        self._render_current_page()
        main_row = toga.Box(style=Pack(direction=ROW, flex=1))
        if self.model.bundle.layout_direction == "rtl":
            main_row.add(toga.ScrollContainer(content=self.page_content, style=Pack(flex=1)))
            main_row.add(nav)
        else:
            main_row.add(nav)
            main_row.add(toga.ScrollContainer(content=self.page_content, style=Pack(flex=1)))
        self.terminal_box = self._terminal_pane()
        return toga.Box(children=[top, main_row, self.terminal_box], style=Pack(direction=COLUMN, flex=1))

    def _top_bar(self) -> toga.Box:
        title = toga.Label(f"{self.model.bundle.manifest.get('textIcon', '')} {self.model.bundle.display_name}", style=Pack(font_weight="bold", padding=4))
        summary = toga.Label(str(self.model.bundle.manifest.get("summary") or ""), style=Pack(padding=4))
        self.status_label = toga.Label(self._status_text(), style=Pack(padding=4))
        setup = toga.Button("Run setup", on_press=self._run_setup, style=Pack(padding=4))
        workspace = toga.Button("Open workspace", on_press=self._open_workspace, style=Pack(padding=4))
        buttons = toga.Box(children=[setup, workspace], style=Pack(direction=ROW, padding=2))
        return toga.Box(children=[toga.Box(children=[title, buttons], style=Pack(direction=ROW)), summary, self.status_label], style=Pack(direction=COLUMN, padding=6))

    def _sidebar(self) -> toga.Box:
        children: list[toga.Widget] = []
        last_group = None
        for page in self.model.bundle.pages:
            group = page.get("sidebarGroup")
            if group and group != last_group:
                children.append(toga.Label(str(group), style=Pack(font_weight="bold", padding=(8, 4, 2, 4))))
                last_group = group
            title = f"{page.get('textIcon', '')} {page.get('title') or page.get('id')}"
            children.append(toga.Button(title, on_press=self._select_page(page.get("id")), style=Pack(padding=3, width=220)))
        return toga.Box(children=children, style=Pack(direction=COLUMN, padding=8, width=250))

    def _terminal_pane(self) -> toga.Box:
        output = toga.MultilineTextInput(readonly=True, style=Pack(flex=1, height=180))
        tab = TerminalTab("main", "Main", output)
        self.terminal_tabs[tab.identifier] = tab
        output.value = "Ready. Command output will appear here.\n"
        return toga.Box(children=[toga.Label("Terminal / logs", style=Pack(font_weight="bold", padding=4)), output], style=Pack(direction=COLUMN, padding=8))

    def _render_current_page(self) -> None:
        if self.page_content is None:
            return
        self.page_content.clear()
        page = self._current_page()
        self.page_content.add(toga.Label(str(page.get("title") or page.get("id")), style=Pack(font_weight="bold", font_size=16, padding=4)))
        if page.get("summary"):
            self.page_content.add(toga.Label(str(page["summary"]), style=Pack(padding=4)))
        for section in page.get("sections", []) or []:
            self._render_section(section)

    def _render_section(self, section: dict) -> None:
        assert self.page_content is not None
        box = toga.Box(style=Pack(direction=COLUMN, padding=8))
        if section.get("title"):
            box.add(toga.Label(f"{section.get('textIcon', '')} {section['title']}", style=Pack(font_weight="bold", padding=3)))
        if section.get("summary") or section.get("subtitle"):
            box.add(toga.Label(str(section.get("summary") or section.get("subtitle")), style=Pack(padding=3)))
        for control in section.get("controls", []) or []:
            box.add(self._render_control(control))
        action_row = toga.Box(style=Pack(direction=ROW, padding=3))
        for action in section.get("actions", []) or []:
            action_row.add(self._action_button(action))
        if section.get("actions"):
            box.add(action_row)
        self.page_content.add(box)

    def _render_control(self, control: dict) -> toga.Widget:
        kind = control.get("kind")
        if kind == "dropdown":
            items = [option.get("title") or option.get("id") for option in control.get("options", []) or []]
            widget = toga.Selection(items=items or [control.get("value") or ""], on_change=self._field_changed(control.get("id")))
            return self._labeled(control, widget)
        if kind == "toggle":
            widget = toga.Switch(str(control.get("label") or control.get("id")), on_change=self._field_changed(control.get("id")))
            return widget
        if kind == "libraryList":
            return self._library_list(control)
        if kind == "configEditor":
            return self._config_editor(control)
        value = self.model.state.field_values.get(str(control.get("id")), str(control.get("value") or ""))
        widget = toga.TextInput(value=value, placeholder=str(control.get("placeholder") or ""), on_change=self._field_changed(control.get("id")), style=Pack(flex=1))
        return self._labeled(control, widget)

    def _labeled(self, control: dict, widget: toga.Widget) -> toga.Box:
        label = toga.Label(str(control.get("label") or control.get("id")), style=Pack(width=180, padding=3))
        return toga.Box(children=[label, widget], style=Pack(direction=ROW, padding=3))

    def _library_list(self, control: dict) -> toga.Box:
        box = toga.Box(style=Pack(direction=COLUMN, padding=4))
        box.add(toga.Label(str(control.get("label") or control.get("id")), style=Pack(font_weight="bold", padding=3)))
        rows = hydrate_rows(control)
        if not rows:
            box.add(toga.Label("No rows loaded. Use data-source refresh by switching pages or running related actions.", style=Pack(padding=3)))
            return box
        for row in rows:
            row_values = row_context_values(row)
            line = f"{row.get('title') or row.get('id')} · {row.get('status') or ''}"
            row_box = toga.Box(children=[toga.Label(line, style=Pack(flex=1, padding=3))], style=Pack(direction=ROW))
            for action in control.get("rowActions", []) or []:
                row_box.add(self._action_button(action, row_values))
            box.add(row_box)
        return box

    def _config_editor(self, control: dict) -> toga.Box:
        box = toga.Box(style=Pack(direction=COLUMN, padding=4))
        box.add(toga.Label(str(control.get("label") or control.get("id")), style=Pack(font_weight="bold", padding=3)))
        for setting in control.get("settings", []) or []:
            setting_control = {**setting, "id": setting.get("id"), "label": setting.get("label")}
            box.add(self._render_control(setting_control))
        box.add(toga.Button("Save settings", on_press=lambda _widget: self.model.save_config(control), style=Pack(padding=3)))
        return box

    def _action_button(self, action: dict, row_values: dict | None = None) -> toga.Button:
        state = self.model.action_state(action, row_values)
        title = str(action.get("title") or action.get("id"))
        if not state.enabled and state.reason:
            title = f"{title} ({state.reason})"
        button = toga.Button(title, on_press=self._run_action(action, row_values), enabled=state.enabled, style=Pack(padding=3))
        return button

    def _field_changed(self, field_id: str | None):
        def handler(widget):
            if not field_id:
                return
            value = getattr(widget, "value", None)
            if value is None:
                value = getattr(widget, "is_on", "")
            self.model.state.field_values[str(field_id)] = str(value)
            self._render_current_page()
        return handler

    def _select_page(self, page_id: str | None):
        def handler(_widget):
            if page_id:
                self.model.state.selected_page_id = str(page_id)
                try:
                    self.model.refresh_data_sources_for_page(str(page_id))
                except Exception as error:
                    self._append_terminal(f"Data-source warning: {error}")
                self._render_current_page()
        return handler

    def _run_action(self, action: dict, row_values: dict | None = None):
        def handler(_widget):
            command = action.get("command") or {}
            context = self.model.context(row_values)
            executable, args = render_command(command, context)
            command_line = display_command((executable, args))
            tab_id = str(uuid.uuid4())
            self._append_terminal(f"$ {command_line}")
            env = os.environ.copy()
            self.runner.start(tab_id, [executable, *args], str(self.model.bundle.bundle_root), env, self._append_terminal, self._finish_action(action))
        return handler

    def _finish_action(self, action: dict):
        def handler(code: int | None, status: str):
            self._append_terminal(f"[{status}] {action.get('title') or action.get('id')} exited {code}")
            try:
                self.model.refresh_data_sources_for_page(self.model.state.selected_page_id)
            except Exception as error:
                self._append_terminal(f"Refresh warning: {error}")
        return handler

    def _run_setup(self, _widget) -> None:
        for step in (self.model.bundle.manifest.get("setup") or {}).get("steps", []) or []:
            self._append_terminal(f"setup: {step.get('label') or step.get('id')} ({step.get('kind')})")

    def _open_workspace(self, _widget) -> None:
        self._append_terminal(f"workspace: {self.model.bundle.workspace_root}")
        if sys_open := _open_command(self.model.bundle.workspace_root):
            try:
                os.spawnlp(os.P_NOWAIT, sys_open[0], *sys_open)
            except OSError as error:
                self._append_terminal(f"open failed: {error}")

    def _append_terminal(self, line: str) -> None:
        tab = self.terminal_tabs.get("main")
        if not tab:
            return
        existing = tab.output.value or ""
        tab.output.value = existing + time.strftime("%H:%M:%S ") + line + "\n"

    def _current_page(self) -> dict:
        for page in self.model.bundle.pages:
            if page.get("id") == self.model.state.selected_page_id:
                return page
        return self.model.bundle.pages[0] if self.model.bundle.pages else {"id": "empty", "title": "No pages"}

    def _status_text(self) -> str:
        return f"{self.model.bundle.localization_code} · {self.model.bundle.layout_direction} · workspace {self.model.bundle.workspace_root}"

    def _on_close(self, _window) -> bool:
        self.runner.cancel_all()
        return True

    def _emit_benchmark(self) -> None:
        snapshot = self.model.render_snapshot()
        metrics = {
            "ui_ready_ms": round((time.perf_counter() - self.benchmark_started) * 1000, 3),
            "pages": snapshot["page_count"],
            "controls": snapshot["control_count"],
            "actions": snapshot["action_count"],
            "setup_steps": snapshot["setup_steps"],
            "terminal_text_direction": snapshot["terminal_text_direction"],
            "layout_direction": snapshot["layout_direction"],
            "surface": "toga",
        }
        for key, value in metrics.items():
            print(f"metric {key}={value}", flush=True)
        if self.benchmark_output:
            self.benchmark_output.parent.mkdir(parents=True, exist_ok=True)
            self.benchmark_output.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")


def _open_command(path: Path) -> list[str] | None:
    if os.name != "posix":
        return None
    if os.uname().sysname == "Darwin":
        return ["open", str(path)]
    return ["xdg-open", str(path)]


def run_app(model: RuntimeModel, *, benchmark_started: float | None = None, benchmark_output: Path | None = None) -> None:
    GUIForCLITogaApp(model, benchmark_started=benchmark_started, benchmark_output=benchmark_output).main_loop()
