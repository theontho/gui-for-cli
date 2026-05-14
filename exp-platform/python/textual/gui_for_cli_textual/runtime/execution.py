from __future__ import annotations

import asyncio
import json
import os
import signal
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Awaitable, Callable

from .bundle import Bundle
from .interpolation import CommandContext, interpolate, rendered_command

LogCallback = Callable[[str], Awaitable[None] | None]


@dataclass
class ProcessResult:
    exit_code: int
    output: str
    cancelled: bool = False


@dataclass
class RunningProcess:
    process: asyncio.subprocess.Process
    output: list[str] = field(default_factory=list)

    async def cancel(self) -> None:
        if self.process.returncode is not None:
            return
        pid = self.process.pid
        if os.name == "nt":
            subprocess.run(["taskkill", "/T", "/F", "/PID", str(pid)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        else:
            try:
                os.killpg(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                await asyncio.wait_for(self.process.wait(), timeout=2)
            except asyncio.TimeoutError:
                try:
                    os.killpg(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass


async def run_command(command: dict[str, Any], context: CommandContext, on_log: LogCallback | None = None) -> ProcessResult:
    rendered = rendered_command(command, context)
    proc = await asyncio.create_subprocess_exec(
        rendered["executable"],
        *rendered["arguments"],
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        start_new_session=(os.name != "nt"),
    )
    running = RunningProcess(proc)
    assert proc.stdout is not None
    try:
        async for raw in proc.stdout:
            line = raw.decode(errors="replace")
            running.output.append(line)
            if on_log:
                maybe = on_log(line)
                if asyncio.iscoroutine(maybe):
                    await maybe
        exit_code = await proc.wait()
        return ProcessResult(exit_code=exit_code, output="".join(running.output))
    except asyncio.CancelledError:
        await running.cancel()
        return ProcessResult(exit_code=-15, output="".join(running.output), cancelled=True)


def run_data_source(data_source: dict[str, Any], context: CommandContext, bundle: Bundle, timeout: float = 12.0) -> dict[str, Any]:
    path = interpolate(data_source.get("path"), context)
    executable = Path(path)
    if not executable.is_absolute():
        executable = bundle.bundle_root / executable
    arguments = [interpolate(arg, context) for arg in data_source.get("arguments") or []]
    cmd = [str(executable), *arguments]
    if executable.suffix == ".py":
        cmd = [sys.executable, str(executable), *arguments]
    env = data_source_env(context, bundle)
    for key, value in (data_source.get("environment") or {}).items():
        env[str(key)] = interpolate(value, context)
    cwd = bundle.bundle_root
    if data_source.get("workingDirectory"):
        cwd = bundle.bundle_root / interpolate(data_source["workingDirectory"], context)
    result = subprocess.run(cmd, cwd=cwd, env=env, text=True, capture_output=True, timeout=timeout, check=False)
    if result.returncode != 0:
        message = (result.stderr or result.stdout or f"data source exited {result.returncode}").strip()
        raise RuntimeError(message)
    payload = json.loads(result.stdout or "{}")
    if not isinstance(payload, dict):
        raise ValueError("data source output must be a JSON object")
    return payload


def data_source_env(context: CommandContext, bundle: Bundle) -> dict[str, str]:
    env = os.environ.copy()
    env["GUI_FOR_CLI_BUNDLE_ROOT"] = str(bundle.bundle_root)
    env["GUI_FOR_CLI_BUNDLE_WORKSPACE"] = str(bundle.workspace_root)
    for key, value in context.field_values.items():
        env[f"GUI_FOR_CLI_FIELD_{key}"] = str(value or "")
    for key, value in context.config_values.items():
        env[f"GUI_FOR_CLI_CONFIG_{key}"] = str(value or "")
    return env
