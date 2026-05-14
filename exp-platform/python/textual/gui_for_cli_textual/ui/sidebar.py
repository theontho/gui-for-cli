from __future__ import annotations

from textual.app import ComposeResult
from textual.widgets import Label, ListItem, ListView

from gui_for_cli_runtime.bundle import Bundle


class Sidebar(ListView):
    DEFAULT_CSS = "Sidebar { width: 28; min-width: 22; border: round $accent; }"

    def __init__(self, bundle: Bundle, selected_page_id: str | None) -> None:
        super().__init__(id="sidebar")
        self.bundle = bundle
        self.selected_page_id = selected_page_id

    def compose(self) -> ComposeResult:
        for page in self.bundle.manifest.get("pages") or []:
            icon = page.get("textIcon") or "•"
            label = self.bundle.strings.text(page.get("title") or page.get("id"))
            item = ListItem(Label(f"{icon}  {label}"), name=str(page.get("id")))
            yield item
