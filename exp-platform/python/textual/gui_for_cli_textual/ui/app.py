from __future__ import annotations

import asyncio
from typing import Any

from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.widgets import Checkbox, Footer, Header, Input, ListView, Select, Switch

from ..args import TextualArgs
from gui_for_cli_runtime.bundle import Bundle
from gui_for_cli_runtime.execution import run_command, run_data_source
from gui_for_cli_runtime.state import RuntimeState, action_key, build_core_state
from .page_view import PageView, dom_id
from .sidebar import Sidebar
from .terminal import TerminalPane


class GUIForCLITextualApp(App):
    CSS = """
    Screen { layout: vertical; }
    #body { height: 1fr; }
    #main-column { width: 1fr; }
    """
    BINDINGS = [("q", "quit", "Quit"), ("r", "refresh_data", "Refresh data"), ("ctrl+c", "cancel_active", "Cancel command")]

    def __init__(self, bundle: Bundle, state: RuntimeState, args: TextualArgs) -> None:
        super().__init__()
        self.bundle = bundle
        self.state = state
        self.args = args
        self.running: dict[str, asyncio.Task] = {}

    def compose(self) -> ComposeResult:
        self.title = self.bundle.display_name
        yield Header(show_clock=True)
        with Horizontal(id="body"):
            if not self.bundle.rtl_layout:
                yield Sidebar(self.bundle, self.state.selected_page_id)
            with Vertical(id="main-column"):
                yield PageView(self.bundle, self.state)
                yield TerminalPane()
            if self.bundle.rtl_layout:
                yield Sidebar(self.bundle, self.state.selected_page_id)
        yield Footer()

    async def on_mount(self) -> None:
        await self.refresh_data_sources()

    async def on_list_view_selected(self, event: ListView.Selected) -> None:
        page_id = getattr(event.item, "name", None)
        if page_id:
            self.state.selected_page_id = str(page_id)
            await self.refresh_data_sources()
            self.refresh_page()

    async def on_input_changed(self, event: Input.Changed) -> None:
        widget_id = event.input.id or ""
        parts = widget_id.split("--")
        if parts[0] == "field" and len(parts) >= 2:
            self.state.field_values[parts[1]] = event.value
        elif parts[0] == "config" and len(parts) >= 3:
            self.state.config_values[f"{parts[1]}.{parts[2]}"] = event.value
            self.state.config_values[parts[2]] = event.value
        self.refresh_page()

    async def on_select_changed(self, event: Select.Changed) -> None:
        widget_id = event.select.id or ""
        parts = widget_id.split("--")
        if parts[0] == "field" and len(parts) >= 2:
            self.state.field_values[parts[1]] = str(event.value or "")
            self.refresh_page()

    async def on_checkbox_changed(self, event: Checkbox.Changed) -> None:
        widget_id = event.checkbox.id or ""
        parts = widget_id.split("--")
        if parts[0] == "check" and len(parts) >= 3:
            selected = set(self.state.checked_options.get(parts[1], set()))
            if event.value:
                selected.add(parts[2])
            else:
                selected.discard(parts[2])
            self.state.checked_options[parts[1]] = selected
            self.refresh_page()

    async def on_switch_changed(self, event: Switch.Changed) -> None:
        widget_id = event.switch.id or ""
        parts = widget_id.split("--")
        if parts[0] == "field" and len(parts) >= 2:
            self.state.field_values[parts[1]] = bool(event.value)
            self.refresh_page()

    async def on_button_pressed(self, event) -> None:
        button_id = event.button.id or ""
        if button_id == "cancel-active":
            await self.cancel_active_command()
            return
        if not button_id.startswith("action--"):
            return
        action_state = self.action_for_button(button_id)
        if not action_state:
            return
        terminal = self.query_one(TerminalPane)
        if action_state.disabled_reason:
            terminal.append("main", f"{action_state.title}: {action_state.disabled_reason}")
            return
        entry_id = terminal.add_entry(action_state.title)
        terminal.append(entry_id, f"$ {action_state.command_display}")
        task = asyncio.create_task(self.execute_bundle_action(entry_id, action_state.action))
        self.running[entry_id] = task

    async def execute_bundle_action(self, entry_id: str, action: dict[str, Any]) -> None:
        terminal = self.query_one(TerminalPane)
        try:
            result = await run_command(action.get("command") or {}, self.state.context(self.bundle), lambda line: terminal.append(entry_id, line))
            status = "cancelled" if result.cancelled else ("ok" if result.exit_code == 0 else "failed")
            terminal.append(entry_id, f"exit {result.exit_code}")
            terminal.set_status(entry_id, status)
            await self.refresh_data_sources()
            self.refresh_page()
        finally:
            self.running.pop(entry_id, None)

    async def cancel_active_command(self) -> None:
        terminal = self.query_one(TerminalPane)
        task = self.running.get(terminal.selected)
        if task:
            terminal.set_status(terminal.selected, "cancelled")
            task.cancel()
            await asyncio.sleep(0)

    async def action_refresh_data(self) -> None:
        await self.refresh_data_sources()
        self.refresh_page()

    async def action_cancel_active(self) -> None:  # binding target
        await self.cancel_active_command()

    async def refresh_data_sources(self) -> None:
        page = self.current_page()
        if not page:
            return
        context = self.state.context(self.bundle)
        for section in page.get("sections") or []:
            section_key = f"section:{section.get('id')}"
            if section.get("dataSource"):
                await self.load_data_source(section_key, section["dataSource"], context)
            section_values = self.state.data_source_payloads.get(section_key, {}).get("values") or {}
            section_context = self.state.context(self.bundle, section_values=section_values)
            for control in section.get("controls") or []:
                if control.get("dataSource"):
                    await self.load_data_source(f"control:{control.get('id')}", control["dataSource"], section_context)

    async def load_data_source(self, key: str, data_source: dict[str, Any], context) -> None:
        try:
            payload = await asyncio.to_thread(run_data_source, data_source, context, self.bundle)
            self.state.data_source_payloads[key] = payload
            self.state.data_source_errors.pop(key, None)
        except Exception as exc:
            self.state.data_source_payloads.pop(key, None)
            self.state.data_source_errors[key] = str(exc)
            self.query_one(TerminalPane).append("main", f"Data source {key}: {exc}")

    def action_for_button(self, button_id: str):
        core = build_core_state(self.bundle, self.state)
        for key, action_state in core.action_states.items():
            if button_id == dom_id("action", key):
                return action_state
        return None

    def refresh_page(self) -> None:
        self.query_one(PageView).refresh(recompose=True)

    def current_page(self) -> dict | None:
        pages = self.bundle.manifest.get("pages") or []
        return next((page for page in pages if page.get("id") == self.state.selected_page_id), pages[0] if pages else None)
