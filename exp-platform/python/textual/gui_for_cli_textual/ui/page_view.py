from __future__ import annotations

from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical
from textual.widget import Widget
from textual.widgets import Button, Checkbox, DataTable, Input, Label, Select, Static, Switch

from gui_for_cli_runtime.bundle import Bundle
from gui_for_cli_runtime.state import RuntimeState, action_key, build_core_state, hydrated_rows


class PageView(Widget):
    DEFAULT_CSS = """
    PageView { height: 1fr; overflow-y: auto; padding: 1 2; }
    .section { border: round $surface; padding: 1; margin-bottom: 1; }
    .actions { height: auto; }
    .destructive { color: $error; }
    """

    def __init__(self, bundle: Bundle, state: RuntimeState) -> None:
        super().__init__(id="page-view")
        self.bundle = bundle
        self.state = state

    def compose(self) -> ComposeResult:
        page = self.current_page()
        if not page:
            yield Static("No pages in bundle.")
            return
        strings = self.bundle.strings
        yield Label(f"[b]{strings.text(page.get('title'))}[/b]")
        yield Static(strings.text(page.get("summary")))
        core = build_core_state(self.bundle, self.state)
        rendered_page = next((item for item in core.pages if item.get("id") == page.get("id")), page)
        for section in rendered_page.get("sections") or []:
            with Vertical(classes="section"):
                yield Label(f"[b]{section.get('textIcon', '')} {strings.text(section.get('title') or section.get('id'))}[/b]")
                if section.get("summary"):
                    yield Static(strings.text(section.get("summary")))
                if section.get("subtitle"):
                    yield Static(strings.text(section.get("subtitle")))
                for control in section.get("controls") or []:
                    yield from self.render_control(control)
                with Horizontal(classes="actions"):
                    for action_state in section.get("actionStates") or []:
                        if not action_state.visible:
                            continue
                        variant = "error" if action_state.action.get("role") == "destructive" else "default"
                        button = Button(action_state.title, id=dom_id("action", action_key(section, action_state.action)), variant=variant)
                        button.disabled = action_state.disabled_reason is not None
                        button.tooltip = action_state.disabled_reason or strings.text(action_state.action.get("tooltip"))
                        yield button

    def render_control(self, control: dict) -> ComposeResult:
        kind = control.get("kind") or "text"
        label = self.bundle.strings.text(control.get("label") or control.get("id"))
        control_id = str(control.get("id"))
        if kind == "configEditor":
            yield Label(label)
            for setting in control.get("settings") or []:
                setting_id = str(setting.get("id"))
                value = str(self.state.config_values.get(f"{control_id}.{setting_id}") or self.state.config_values.get(setting_id) or "")
                yield Input(value=value, placeholder=self.bundle.strings.text(setting.get("label") or setting_id), id=dom_id("config", control_id, setting_id), classes="path-field" if setting.get("kind") == "path" else "")
            return
        if kind == "dropdown":
            options = [(self.bundle.strings.text(option.get("title") or option.get("id")), str(option.get("id"))) for option in control.get("options") or []]
            value = str(self.state.field_values.get(control_id) or (options[0][1] if options else ""))
            yield Label(label)
            yield Select(options or [("", "")], value=value if options else "", allow_blank=not options, id=dom_id("field", control_id))
            return
        if kind == "toggle":
            yield Horizontal(Label(label), Switch(value=bool(self.state.field_values.get(control_id)), id=dom_id("field", control_id)))
            return
        if kind == "checkboxGroup":
            yield Label(label)
            selected = self.state.checked_options.get(control_id, set())
            for option in control.get("options") or []:
                oid = str(option.get("id"))
                yield Checkbox(self.bundle.strings.text(option.get("title") or oid), value=oid in selected, id=dom_id("check", control_id, oid))
            return
        if kind == "libraryList":
            yield Label(label)
            table = DataTable(id=dom_id("table", control_id))
            table.add_columns(*[self.bundle.strings.text(column.get("title") or column.get("id")) for column in control.get("columns") or []])
            for row in hydrated_rows(control):
                table.add_row(*[str((row.get("values") or {}).get(column.get("id"), "")) for column in control.get("columns") or []], label=str(row.get("title") or row.get("id")))
            yield table
            return
        value = str(self.state.field_values.get(control_id) or "")
        yield Label(label)
        yield Input(value=value, placeholder=self.bundle.strings.text(control.get("placeholder") or ""), id=dom_id("field", control_id), classes="path-field" if kind == "path" else "")

    def current_page(self) -> dict | None:
        pages = self.bundle.manifest.get("pages") or []
        return next((page for page in pages if page.get("id") == self.state.selected_page_id), pages[0] if pages else None)


def dom_id(*parts: str) -> str:
    text = "--".join(parts)
    return "".join(ch if ch.isalnum() or ch in "_-" else "-" for ch in text)
