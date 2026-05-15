from __future__ import annotations

import tkinter as tk
import json
import threading
import time
from pathlib import Path
from tkinter import ttk
from typing import Any, Callable

from gui_for_cli_runtime.bundle import Bundle
from gui_for_cli_runtime.execution import DATA_SOURCE_EXCEPTIONS, CommandJob, run_data_source
from gui_for_cli_runtime.state import RuntimeState, action_key, build_core_state, hydrated_rows


class TkinterRendererApp:
    def __init__(
        self,
        bundle: Bundle,
        state: RuntimeState,
        *,
        benchmark_started: float | None = None,
        benchmark_output: Path | None = None,
        core_metrics: dict[str, object] | None = None,
    ) -> None:
        self.bundle = bundle
        self.state = state
        self.benchmark_started = benchmark_started
        self.benchmark_output = benchmark_output
        self.core_metrics = core_metrics or {}
        self.root = tk.Tk()
        self.root.title(bundle.display_name)
        self.action_buttons: dict[str, ttk.Button] = {}
        self.terminal_tabs: dict[str, tk.Text] = {}
        self.jobs: dict[str, CommandJob] = {}
        self.pending_data_sources: set[str] = set()
        self.next_tab = 1
        self._build_shell()

    def run(self) -> None:
        self.root.after(50, self._benchmark_ready if self.benchmark_started is not None else self.refresh_data_sources)
        self.root.mainloop()

    def _build_shell(self) -> None:
        self.root.geometry("1180x780")
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        body = ttk.Frame(self.root)
        body.grid(row=0, column=0, sticky="nsew")
        body.columnconfigure(1 if not self.bundle.rtl_layout else 0, weight=1)
        body.rowconfigure(0, weight=1)

        self.sidebar = tk.Listbox(body, exportselection=False, width=28)
        for page in self.bundle.manifest.get("pages") or []:
            icon = page.get("textIcon") or "-"
            self.sidebar.insert(tk.END, f"{icon}  {self.bundle.strings.text(page.get('title') or page.get('id'))}")
        self.sidebar.bind("<<ListboxSelect>>", self._on_page_selected)

        self.main = ttk.PanedWindow(body, orient=tk.VERTICAL)
        self.page_frame = ttk.Frame(self.main)
        self.terminal_frame = ttk.Frame(self.main)
        self.main.add(self.page_frame, weight=3)
        self.main.add(self.terminal_frame, weight=1)

        if self.bundle.rtl_layout:
            self.main.grid(row=0, column=0, sticky="nsew")
            self.sidebar.grid(row=0, column=1, sticky="ns")
        else:
            self.sidebar.grid(row=0, column=0, sticky="ns")
            self.main.grid(row=0, column=1, sticky="nsew")

        if self.state.selected_page_id:
            page_ids = [str(page.get("id")) for page in self.bundle.manifest.get("pages") or []]
            if self.state.selected_page_id in page_ids:
                self.sidebar.selection_set(page_ids.index(self.state.selected_page_id))
        self._build_terminal()
        self.refresh_page()

    def _build_terminal(self) -> None:
        toolbar = ttk.Frame(self.terminal_frame)
        toolbar.pack(fill=tk.X)
        ttk.Button(toolbar, text="Cancel", command=self.cancel_active).pack(side=tk.RIGHT)
        ttk.Button(toolbar, text="Close tab", command=self.close_active_terminal).pack(side=tk.RIGHT, padx=(0, 6))
        self.terminal = ttk.Notebook(self.terminal_frame)
        self.terminal.pack(fill=tk.BOTH, expand=True)
        self.add_terminal_tab("main", "Main", initial="Ready.")

    def add_terminal_tab(self, tab_id: str, title: str, initial: str = "") -> None:
        text = tk.Text(self.terminal, wrap=tk.WORD, height=9, undo=False)
        text.configure(font=("Menlo", 11))
        self.terminal.add(text, text=title)
        self.terminal_tabs[tab_id] = text
        if initial:
            self.append_terminal(tab_id, initial)
        self.terminal.select(text)

    def append_terminal(self, tab_id: str, message: str) -> None:
        text = self.terminal_tabs.get(tab_id)
        if text is None:
            return
        text.configure(state=tk.NORMAL)
        text.insert(tk.END, message if message.endswith("\n") else f"{message}\n")
        text.see(tk.END)
        text.configure(state=tk.DISABLED)

    def set_terminal_title(self, tab_id: str, title: str) -> None:
        text = self.terminal_tabs.get(tab_id)
        if text is None:
            return
        self.terminal.tab(text, text=title)

    def close_active_terminal(self) -> None:
        current = self.terminal.select()
        if not current:
            return
        tab_id = self._tab_id_for_widget(current)
        if tab_id == "main":
            return
        self.cancel_tab(tab_id)
        text = self.terminal_tabs.pop(tab_id, None)
        if text is not None:
            self.terminal.forget(text)

    def cancel_active(self) -> None:
        current = self.terminal.select()
        if current:
            self.cancel_tab(self._tab_id_for_widget(current))

    def cancel_tab(self, tab_id: str) -> None:
        job = self.jobs.get(tab_id)
        if job:
            self.set_terminal_title(tab_id, f"cancelled {job.title}")
            job.cancel()

    def refresh_page(self) -> None:
        for child in self.page_frame.winfo_children():
            child.destroy()
        page = self.current_page()
        if not page:
            ttk.Label(self.page_frame, text="No pages in bundle.").pack(anchor=tk.W, padx=16, pady=16)
            return

        canvas = tk.Canvas(self.page_frame, highlightthickness=0)
        scrollbar = ttk.Scrollbar(self.page_frame, orient=tk.VERTICAL, command=canvas.yview)
        content = ttk.Frame(canvas)
        content.bind("<Configure>", lambda _event: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=content, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        strings = self.bundle.strings
        ttk.Label(content, text=strings.text(page.get("title")), font=("", 18, "bold")).pack(anchor=tk.W, padx=18, pady=(18, 2))
        if page.get("summary"):
            ttk.Label(content, text=strings.text(page.get("summary")), wraplength=860).pack(anchor=tk.W, padx=18, pady=(0, 12))
        core = build_core_state(self.bundle, self.state)
        rendered_page = next((item for item in core.pages if item.get("id") == page.get("id")), page)
        self.action_buttons = {}
        for section in rendered_page.get("sections") or []:
            self.render_section(content, section)

    def render_section(self, parent: tk.Widget, section: dict[str, Any]) -> None:
        strings = self.bundle.strings
        frame = ttk.LabelFrame(parent, text=f"{section.get('textIcon', '')} {strings.text(section.get('title') or section.get('id'))}".strip())
        frame.pack(fill=tk.X, expand=True, padx=18, pady=8)
        if section.get("summary"):
            ttk.Label(frame, text=strings.text(section.get("summary")), wraplength=820).pack(anchor=tk.W, padx=10, pady=(8, 2))
        if section.get("subtitle"):
            ttk.Label(frame, text=strings.text(section.get("subtitle")), wraplength=820).pack(anchor=tk.W, padx=10, pady=(0, 8))
        for control in section.get("controls") or []:
            self.render_control(frame, control)
        actions = ttk.Frame(frame)
        actions.pack(anchor=tk.W, padx=10, pady=10)
        for action_state in section.get("actionStates") or []:
            if not action_state.visible:
                continue
            button = ttk.Button(actions, text=action_state.title, command=lambda s=action_state: self.run_action(s))
            if action_state.disabled_reason:
                button.state(["disabled"])
            button.pack(side=tk.LEFT, padx=(0, 8))
            self.action_buttons[action_key(section, action_state.action)] = button

    def render_control(self, parent: tk.Widget, control: dict[str, Any]) -> None:
        kind = control.get("kind") or "text"
        control_id = str(control.get("id"))
        label = self.bundle.strings.text(control.get("label") or control_id)
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, padx=10, pady=5)
        ttk.Label(row, text=label, width=24).pack(side=tk.LEFT, anchor=tk.N)

        if kind == "configEditor":
            settings = ttk.Frame(row)
            settings.pack(fill=tk.X, expand=True)
            for setting in control.get("settings") or []:
                setting_id = str(setting.get("id"))
                value = str(self.state.config_values.get(f"{control_id}.{setting_id}") or self.state.config_values.get(setting_id) or "")
                self._entry(settings, value, lambda text, cid=control_id, sid=setting_id: self._set_config(cid, sid, text))
            return
        if kind == "dropdown":
            values = [str(option.get("id")) for option in control.get("options") or []]
            combo = ttk.Combobox(row, values=values, state="readonly")
            combo.set(str(self.state.field_values.get(control_id) or (values[0] if values else "")))
            combo.bind("<<ComboboxSelected>>", lambda event, cid=control_id: self._set_field(cid, event.widget.get()))
            combo.pack(fill=tk.X, expand=True)
            return
        if kind == "toggle":
            var = tk.BooleanVar(value=bool(self.state.field_values.get(control_id)))
            ttk.Checkbutton(row, variable=var, command=lambda cid=control_id, v=var: self._set_field(cid, v.get())).pack(side=tk.LEFT)
            return
        if kind == "checkboxGroup":
            selected = self.state.checked_options.get(control_id, set())
            for option in control.get("options") or []:
                option_id = str(option.get("id"))
                var = tk.BooleanVar(value=option_id in selected)
                ttk.Checkbutton(
                    row,
                    text=self.bundle.strings.text(option.get("title") or option_id),
                    variable=var,
                    command=lambda cid=control_id, oid=option_id, v=var: self._set_option(cid, oid, v.get()),
                ).pack(side=tk.LEFT, padx=(0, 8))
            return
        if kind == "libraryList":
            columns = [str(column.get("id")) for column in control.get("columns") or []]
            tree = ttk.Treeview(row, columns=columns, show="tree headings", height=6)
            tree.heading("#0", text="Item")
            for column in control.get("columns") or []:
                cid = str(column.get("id"))
                tree.heading(cid, text=self.bundle.strings.text(column.get("title") or cid))
            for item in hydrated_rows(control):
                tree.insert("", tk.END, text=str(item.get("title") or item.get("id")), values=[str((item.get("values") or {}).get(cid, "")) for cid in columns])
            tree.pack(fill=tk.X, expand=True)
            return
        self._entry(row, str(self.state.field_values.get(control_id) or ""), lambda text, cid=control_id: self._set_field(cid, text))

    def _entry(self, parent: tk.Widget, value: str, on_change: Callable[[str], None]) -> None:
        var = tk.StringVar(value=value)
        entry = ttk.Entry(parent, textvariable=var)

        pending_after: str | None = None

        def apply_change() -> None:
            nonlocal pending_after
            pending_after = None
            if entry.winfo_exists():
                on_change(var.get())

        def schedule_change(*_args) -> None:
            nonlocal pending_after
            if pending_after is not None:
                entry.after_cancel(pending_after)
            pending_after = entry.after(300, apply_change)

        var.trace_add("write", schedule_change)
        entry.pack(fill=tk.X, expand=True, pady=2)

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
            log=lambda line: self.root.after(0, self.append_terminal, tab_id, line),
            done=lambda status, code: self.root.after(0, self._finish_job, tab_id, action_state.title, status, code),
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
        self.pending_data_sources.add(key)

        def worker() -> None:
            try:
                payload = run_data_source(data_source, context, self.bundle)
            except DATA_SOURCE_EXCEPTIONS as exc:
                self.root.after(0, self._finish_data_source_error, key, str(exc))
            else:
                self.root.after(0, self._finish_data_source_success, key, payload)

        threading.Thread(target=worker, daemon=True).start()

    def _finish_data_source_success(self, key: str, payload: dict[str, Any]) -> None:
        self.pending_data_sources.discard(key)
        self.state.data_source_payloads[key] = payload
        self.state.data_source_errors.pop(key, None)
        self.refresh_page()

    def _finish_data_source_error(self, key: str, message: str) -> None:
        self.pending_data_sources.discard(key)
        self.state.data_source_payloads.pop(key, None)
        self.state.data_source_errors[key] = message
        self.append_terminal("main", f"Data source {key}: {message}")
        self.refresh_page()

    def _set_field(self, control_id: str, value: Any) -> None:
        self.state.field_values[control_id] = value
        self.refresh_page()

    def _set_config(self, control_id: str, setting_id: str, value: str) -> None:
        self.state.config_values[f"{control_id}.{setting_id}"] = value
        self.state.config_values[setting_id] = value
        self.refresh_page()

    def _set_option(self, control_id: str, option_id: str, selected: bool) -> None:
        values = set(self.state.checked_options.get(control_id, set()))
        if selected:
            values.add(option_id)
        else:
            values.discard(option_id)
        self.state.checked_options[control_id] = values
        self.refresh_page()

    def _on_page_selected(self, _event: tk.Event) -> None:
        selected = self.sidebar.curselection()
        pages = self.bundle.manifest.get("pages") or []
        if selected and selected[0] < len(pages):
            self.state.selected_page_id = str(pages[selected[0]].get("id"))
            self.refresh_data_sources()
            self.refresh_page()

    def current_page(self) -> dict[str, Any] | None:
        pages = self.bundle.manifest.get("pages") or []
        return next((page for page in pages if page.get("id") == self.state.selected_page_id), pages[0] if pages else None)

    def _tab_id_for_widget(self, widget_name: str) -> str:
        for tab_id, widget in self.terminal_tabs.items():
            if str(widget) == widget_name:
                return tab_id
        return "main"

    def _benchmark_ready(self) -> None:
        self.refresh_data_sources()
        if self.pending_data_sources:
            self.root.after(50, self._emit_benchmark_when_ready)
            return
        self._emit_benchmark_when_ready()

    def _emit_benchmark_when_ready(self) -> None:
        if self.pending_data_sources:
            self.root.after(50, self._emit_benchmark_when_ready)
            return
        self.root.update_idletasks()
        core = build_core_state(self.bundle, self.state)
        metrics = {
            "ui_ready_ms": round((time.perf_counter() - self.benchmark_started) * 1000, 3),
            **self.core_metrics,
            "pages": len(core.pages),
            "actions": core.action_count,
            "controls": core.control_count,
            "surface": "tkinter",
        }
        for key, value in metrics.items():
            print(f"metric {key}={value}", flush=True)
        if self.benchmark_output:
            self.benchmark_output.parent.mkdir(parents=True, exist_ok=True)
            self.benchmark_output.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
