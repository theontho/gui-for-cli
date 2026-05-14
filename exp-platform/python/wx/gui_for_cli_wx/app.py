from __future__ import annotations

import threading
from typing import Any

import wx

from gui_for_cli_runtime.bundle import Bundle
from gui_for_cli_runtime.execution import DATA_SOURCE_EXCEPTIONS, CommandJob, run_data_source
from gui_for_cli_runtime.state import RuntimeState, action_key, build_core_state, hydrated_rows


class WxRendererApp(wx.App):
    def __init__(self, bundle: Bundle, state: RuntimeState) -> None:
        self.bundle = bundle
        self.state = state
        self.jobs: dict[str, CommandJob] = {}
        self.next_tab = 1
        super().__init__(clearSigInt=True)

    def OnInit(self) -> bool:
        self.frame = wx.Frame(None, title=self.bundle.display_name, size=(1180, 780))
        self.terminal_pages: dict[str, wx.TextCtrl] = {}
        self._build_shell()
        self.frame.Show()
        wx.CallAfter(self.refresh_data_sources)
        return True

    def _build_shell(self) -> None:
        root = wx.Panel(self.frame)
        outer = wx.BoxSizer(wx.HORIZONTAL)
        root.SetSizer(outer)

        self.sidebar = wx.ListBox(root, size=(250, -1))
        for page in self.bundle.manifest.get("pages") or []:
            icon = page.get("textIcon") or "-"
            self.sidebar.Append(f"{icon}  {self.bundle.strings.text(page.get('title') or page.get('id'))}")
        self.sidebar.Bind(wx.EVT_LISTBOX, self._on_page_selected)

        self.splitter = wx.SplitterWindow(root, style=wx.SP_LIVE_UPDATE)
        self.page_panel = wx.ScrolledWindow(self.splitter)
        self.page_panel.SetScrollRate(0, 16)
        terminal_panel = wx.Panel(self.splitter)
        self.splitter.SplitHorizontally(self.page_panel, terminal_panel, sashPosition=540)
        self.splitter.SetMinimumPaneSize(120)

        if self.bundle.rtl_layout:
            outer.Add(self.splitter, 1, wx.EXPAND)
            outer.Add(self.sidebar, 0, wx.EXPAND)
        else:
            outer.Add(self.sidebar, 0, wx.EXPAND)
            outer.Add(self.splitter, 1, wx.EXPAND)

        self._build_terminal(terminal_panel)
        self.refresh_page()

    def _build_terminal(self, panel: wx.Panel) -> None:
        sizer = wx.BoxSizer(wx.VERTICAL)
        toolbar = wx.BoxSizer(wx.HORIZONTAL)
        close = wx.Button(panel, label="Close tab")
        cancel = wx.Button(panel, label="Cancel")
        close.Bind(wx.EVT_BUTTON, lambda _event: self.close_active_terminal())
        cancel.Bind(wx.EVT_BUTTON, lambda _event: self.cancel_active())
        toolbar.AddStretchSpacer()
        toolbar.Add(close, 0, wx.RIGHT, 6)
        toolbar.Add(cancel)
        self.terminal = wx.Notebook(panel)
        sizer.Add(toolbar, 0, wx.EXPAND | wx.ALL, 4)
        sizer.Add(self.terminal, 1, wx.EXPAND)
        panel.SetSizer(sizer)
        self.add_terminal_tab("main", "Main", "Ready.")

    def add_terminal_tab(self, tab_id: str, title: str, initial: str = "") -> None:
        text = wx.TextCtrl(self.terminal, style=wx.TE_MULTILINE | wx.TE_READONLY | wx.TE_RICH2)
        self.terminal.AddPage(text, title, select=True)
        self.terminal_pages[tab_id] = text
        if initial:
            self.append_terminal(tab_id, initial)

    def append_terminal(self, tab_id: str, message: str) -> None:
        text = self.terminal_pages.get(tab_id)
        if text:
            text.AppendText(message if message.endswith("\n") else f"{message}\n")

    def set_terminal_title(self, tab_id: str, title: str) -> None:
        text = self.terminal_pages.get(tab_id)
        if not text:
            return
        index = self.terminal.GetPageIndex(text)
        if index != wx.NOT_FOUND:
            self.terminal.SetPageText(index, title)

    def close_active_terminal(self) -> None:
        index = self.terminal.GetSelection()
        if index == wx.NOT_FOUND:
            return
        page = self.terminal.GetPage(index)
        tab_id = self._tab_id_for_page(page)
        if tab_id == "main":
            return
        self.cancel_tab(tab_id)
        self.terminal.DeletePage(index)
        self.terminal_pages.pop(tab_id, None)

    def cancel_active(self) -> None:
        index = self.terminal.GetSelection()
        if index != wx.NOT_FOUND:
            self.cancel_tab(self._tab_id_for_page(self.terminal.GetPage(index)))

    def cancel_tab(self, tab_id: str) -> None:
        job = self.jobs.get(tab_id)
        if job:
            self.set_terminal_title(tab_id, f"cancelled {job.title}")
            job.cancel()

    def refresh_page(self) -> None:
        self.page_panel.DestroyChildren()
        sizer = wx.BoxSizer(wx.VERTICAL)
        self.page_panel.SetSizer(sizer)
        page = self.current_page()
        if not page:
            sizer.Add(wx.StaticText(self.page_panel, label="No pages in bundle."), 0, wx.ALL, 16)
            self.page_panel.Layout()
            return

        strings = self.bundle.strings
        title = wx.StaticText(self.page_panel, label=strings.text(page.get("title")))
        title.SetFont(title.GetFont().Bold().Larger())
        sizer.Add(title, 0, wx.LEFT | wx.RIGHT | wx.TOP, 18)
        if page.get("summary"):
            summary = wx.StaticText(self.page_panel, label=strings.text(page.get("summary")))
            summary.Wrap(860)
            sizer.Add(summary, 0, wx.LEFT | wx.RIGHT | wx.BOTTOM, 18)

        core = build_core_state(self.bundle, self.state)
        rendered_page = next((item for item in core.pages if item.get("id") == page.get("id")), page)
        for section in rendered_page.get("sections") or []:
            self.render_section(sizer, section)
        self.page_panel.FitInside()
        self.page_panel.Layout()

    def render_section(self, parent: wx.BoxSizer, section: dict[str, Any]) -> None:
        strings = self.bundle.strings
        box = wx.StaticBox(self.page_panel, label=f"{section.get('textIcon', '')} {strings.text(section.get('title') or section.get('id'))}".strip())
        sizer = wx.StaticBoxSizer(box, wx.VERTICAL)
        parent.Add(sizer, 0, wx.EXPAND | wx.ALL, 12)
        if section.get("summary"):
            sizer.Add(wx.StaticText(self.page_panel, label=strings.text(section.get("summary"))), 0, wx.ALL, 8)
        for control in section.get("controls") or []:
            self.render_control(sizer, control)
        actions = wx.BoxSizer(wx.HORIZONTAL)
        sizer.Add(actions, 0, wx.ALL, 8)
        for action_state in section.get("actionStates") or []:
            if not action_state.visible:
                continue
            button = wx.Button(self.page_panel, label=action_state.title)
            button.Enable(action_state.disabled_reason is None)
            button.Bind(wx.EVT_BUTTON, lambda _event, s=action_state: self.run_action(s))
            actions.Add(button, 0, wx.RIGHT, 8)

    def render_control(self, parent: wx.BoxSizer, control: dict[str, Any]) -> None:
        kind = control.get("kind") or "text"
        control_id = str(control.get("id"))
        row = wx.BoxSizer(wx.HORIZONTAL)
        parent.Add(row, 0, wx.EXPAND | wx.ALL, 6)
        row.Add(wx.StaticText(self.page_panel, label=self.bundle.strings.text(control.get("label") or control_id), size=(180, -1)), 0, wx.RIGHT, 8)
        if kind == "dropdown":
            values = [str(option.get("id")) for option in control.get("options") or []]
            combo = wx.ComboBox(self.page_panel, value=str(self.state.field_values.get(control_id) or (values[0] if values else "")), choices=values, style=wx.CB_READONLY)
            combo.Bind(wx.EVT_COMBOBOX, lambda event, cid=control_id: self._set_field(cid, event.GetString()))
            row.Add(combo, 1, wx.EXPAND)
            return
        if kind == "toggle":
            check = wx.CheckBox(self.page_panel)
            check.SetValue(bool(self.state.field_values.get(control_id)))
            check.Bind(wx.EVT_CHECKBOX, lambda event, cid=control_id: self._set_field(cid, event.IsChecked()))
            row.Add(check)
            return
        if kind == "checkboxGroup":
            selected = self.state.checked_options.get(control_id, set())
            for option in control.get("options") or []:
                option_id = str(option.get("id"))
                check = wx.CheckBox(self.page_panel, label=self.bundle.strings.text(option.get("title") or option_id))
                check.SetValue(option_id in selected)
                check.Bind(wx.EVT_CHECKBOX, lambda event, cid=control_id, oid=option_id: self._set_option(cid, oid, event.IsChecked()))
                row.Add(check, 0, wx.RIGHT, 8)
            return
        if kind == "libraryList":
            rows = hydrated_rows(control)
            listbox = wx.ListBox(self.page_panel, choices=[str(item.get("title") or item.get("id")) for item in rows])
            row.Add(listbox, 1, wx.EXPAND)
            return
        if kind == "configEditor":
            settings = wx.BoxSizer(wx.VERTICAL)
            row.Add(settings, 1, wx.EXPAND)
            for setting in control.get("settings") or []:
                setting_id = str(setting.get("id"))
                value = str(self.state.config_values.get(f"{control_id}.{setting_id}") or self.state.config_values.get(setting_id) or "")
                entry = wx.TextCtrl(self.page_panel, value=value)
                entry.Bind(wx.EVT_TEXT, lambda event, cid=control_id, sid=setting_id: self._set_config(cid, sid, event.GetString(), refresh=False))
                entry.Bind(wx.EVT_KILL_FOCUS, self._refresh_after_focus)
                settings.Add(entry, 0, wx.EXPAND | wx.BOTTOM, 4)
            return
        entry = wx.TextCtrl(self.page_panel, value=str(self.state.field_values.get(control_id) or ""))
        entry.Bind(wx.EVT_TEXT, lambda event, cid=control_id: self._set_field(cid, event.GetString(), refresh=False))
        entry.Bind(wx.EVT_KILL_FOCUS, self._refresh_after_focus)
        row.Add(entry, 1, wx.EXPAND)

    def run_action(self, action_state) -> None:
        if action_state.disabled_reason:
            self.append_terminal("main", f"{action_state.title}: {action_state.disabled_reason}")
            return
        tab_id = f"run-{self.next_tab}"
        self.next_tab += 1
        self.add_terminal_tab(tab_id, f"running {action_state.title}", f"$ {action_state.command_display}")
        job = CommandJob(
            title=action_state.title,
            action=action_state.action,
            context=self.state.context(self.bundle),
            log=lambda line: wx.CallAfter(self.append_terminal, tab_id, line),
            done=lambda status, code: wx.CallAfter(self._finish_job, tab_id, action_state.title, status, code),
        )
        self.jobs[tab_id] = job
        job.start()

    def _finish_job(self, tab_id: str, title: str, status: str, code: int) -> None:
        self.append_terminal(tab_id, f"exit {code}")
        self.set_terminal_title(tab_id, f"{status} {title}")
        self.jobs.pop(tab_id, None)
        self.refresh_data_sources()

    def refresh_data_sources(self) -> None:
        page = self.current_page()
        if not page:
            return
        context = self.state.context(self.bundle)
        for section in page.get("sections") or []:
            section_key = f"section:{section.get('id')}"
            if section.get("dataSource"):
                self._load_data_source(section_key, section["dataSource"], context)
            section_values = self.state.data_source_payloads.get(section_key, {}).get("values") or {}
            section_context = self.state.context(self.bundle, section_values=section_values)
            for control in section.get("controls") or []:
                if control.get("dataSource"):
                    self._load_data_source(f"control:{control.get('id')}", control["dataSource"], section_context)

    def _load_data_source(self, key: str, data_source: dict[str, Any], context) -> None:
        def worker() -> None:
            try:
                payload = run_data_source(data_source, context, self.bundle)
            except DATA_SOURCE_EXCEPTIONS as exc:
                wx.CallAfter(self._finish_data_source_error, key, str(exc))
            else:
                wx.CallAfter(self._finish_data_source_success, key, payload)

        threading.Thread(target=worker, daemon=True).start()

    def _finish_data_source_success(self, key: str, payload: dict[str, Any]) -> None:
        self.state.data_source_payloads[key] = payload
        self.state.data_source_errors.pop(key, None)
        self.refresh_page()

    def _finish_data_source_error(self, key: str, message: str) -> None:
        self.state.data_source_payloads.pop(key, None)
        self.state.data_source_errors[key] = message
        self.append_terminal("main", f"Data source {key}: {message}")
        self.refresh_page()

    def _set_field(self, control_id: str, value: Any, *, refresh: bool = True) -> None:
        self.state.field_values[control_id] = value
        if refresh:
            self.refresh_page()

    def _set_config(self, control_id: str, setting_id: str, value: str, *, refresh: bool = True) -> None:
        self.state.config_values[f"{control_id}.{setting_id}"] = value
        self.state.config_values[setting_id] = value
        if refresh:
            self.refresh_page()

    def _refresh_after_focus(self, event) -> None:
        event.Skip()
        wx.CallAfter(self.refresh_page)

    def _set_option(self, control_id: str, option_id: str, selected: bool) -> None:
        values = set(self.state.checked_options.get(control_id, set()))
        values.add(option_id) if selected else values.discard(option_id)
        self.state.checked_options[control_id] = values
        self.refresh_page()

    def _on_page_selected(self, event) -> None:
        pages = self.bundle.manifest.get("pages") or []
        index = event.GetSelection()
        if 0 <= index < len(pages):
            self.state.selected_page_id = str(pages[index].get("id"))
            self.refresh_data_sources()
            self.refresh_page()

    def current_page(self) -> dict[str, Any] | None:
        pages = self.bundle.manifest.get("pages") or []
        return next((page for page in pages if page.get("id") == self.state.selected_page_id), pages[0] if pages else None)

    def _tab_id_for_page(self, page: wx.Window) -> str:
        for tab_id, candidate in self.terminal_pages.items():
            if candidate is page:
                return tab_id
        return "main"
