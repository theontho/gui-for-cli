from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical
from textual.reactive import reactive
from textual.widget import Widget
from textual.widgets import Button, Label, RichLog, Select


@dataclass
class TerminalEntry:
    id: str
    title: str
    status: str = "info"
    lines: list[str] = field(default_factory=list)
    task: Any | None = None


class TerminalPane(Widget):
    DEFAULT_CSS = """
    TerminalPane { height: 28%; min-height: 8; border: round $primary; }
    #terminal-log { height: 1fr; }
    #terminal-tabs { width: 1fr; }
    """

    entries: reactive[list[TerminalEntry]] = reactive(
        [TerminalEntry(id="main", title="Main", lines=["Ready."])], recompose=True
    )
    selected: reactive[str] = reactive("main", recompose=True)

    def on_mount(self) -> None:
        self.selected = "main"

    def compose(self) -> ComposeResult:
        options = [(self._tab_label(entry), entry.id) for entry in self.entries]
        yield Vertical(
            Horizontal(Select(options, value=self.selected, allow_blank=False, id="terminal-tabs"), Button("Cancel", id="cancel-active", variant="error")),
            RichLog(id="terminal-log", wrap=True, highlight=False),
        )

    def on_select_changed(self, event: Select.Changed) -> None:
        self.selected = str(event.value)
        self._render_log()

    def add_entry(self, title: str) -> str:
        entry_id = f"run-{len(self.entries)}"
        self.entries = [*self.entries, TerminalEntry(id=entry_id, title=title, status="running")]
        self.selected = entry_id
        self.refresh(recompose=True)
        return entry_id

    def append(self, entry_id: str, text: str) -> None:
        entry = self.entry(entry_id)
        if entry:
            entry.lines.extend(text.rstrip("\n").splitlines() or [""])
        if entry_id == self.selected:
            self._render_log()

    def set_status(self, entry_id: str, status: str) -> None:
        entry = self.entry(entry_id)
        if entry:
            entry.status = status
        self.refresh(recompose=True)

    def entry(self, entry_id: str) -> TerminalEntry | None:
        return next((entry for entry in self.entries if entry.id == entry_id), None)

    def _render_log(self) -> None:
        if not self.is_mounted:
            return
        log = self.query_one("#terminal-log", RichLog)
        log.clear()
        entry = self.entry(self.selected)
        if not entry:
            return
        for line in entry.lines[-400:]:
            log.write(line)

    def _tab_label(self, entry: TerminalEntry) -> str:
        icon = {"running": "⏳", "failed": "✗", "cancelled": "⊘", "ok": "✓"}.get(entry.status, "•")
        return f"{icon} {entry.title}"
