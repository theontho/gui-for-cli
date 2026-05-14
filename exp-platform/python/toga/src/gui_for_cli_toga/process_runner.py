from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable
import os
import signal
import subprocess
import threading

LineCallback = Callable[[str], None]
FinishCallback = Callable[[int | None, str], None]


@dataclass
class ProcessHandle:
    id: str
    command: list[str]
    process: subprocess.Popen[str]
    _finished: threading.Event = field(default_factory=threading.Event)

    def cancel(self) -> None:
        if self.process.poll() is not None:
            return
        try:
            if os.name == "posix":
                os.killpg(os.getpgid(self.process.pid), signal.SIGTERM)
            else:
                self.process.terminate()
        except ProcessLookupError:
            return

    def wait(self, timeout: float | None = None) -> int | None:
        try:
            return self.process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            return None


class ProcessRunner:
    def __init__(self) -> None:
        self._handles: dict[str, ProcessHandle] = {}
        self._lock = threading.Lock()

    def start(
        self,
        identifier: str,
        command: list[str],
        cwd: str,
        env: dict[str, str] | None,
        on_line: LineCallback,
        on_finish: FinishCallback,
    ) -> ProcessHandle:
        popen_kwargs = {}
        if os.name == "posix":
            popen_kwargs["start_new_session"] = True
        process = subprocess.Popen(
            command,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            **popen_kwargs,
        )
        handle = ProcessHandle(identifier, command, process)
        with self._lock:
            self._handles[identifier] = handle
        thread = threading.Thread(target=self._pump, args=(handle, on_line, on_finish), daemon=True)
        thread.start()
        return handle

    def cancel(self, identifier: str) -> None:
        handle = self._handles.get(identifier)
        if handle:
            handle.cancel()

    def cancel_all(self) -> None:
        with self._lock:
            handles = list(self._handles.values())
        for handle in handles:
            handle.cancel()

    def _pump(self, handle: ProcessHandle, on_line: LineCallback, on_finish: FinishCallback) -> None:
        try:
            if handle.process.stdout:
                for line in handle.process.stdout:
                    on_line(line.rstrip("\n"))
            code = handle.process.wait()
            status = "success" if code == 0 else "failed"
            on_finish(code, status)
        finally:
            handle._finished.set()
            with self._lock:
                self._handles.pop(handle.id, None)
