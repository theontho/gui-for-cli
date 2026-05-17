"""Execution primitives for the platform runner."""

from __future__ import annotations

import os
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
if sys.platform.startswith("darwin"):
    CURRENT_OS = "darwin"
elif sys.platform.startswith("win"):
    CURRENT_OS = "windows"
elif sys.platform.startswith("linux"):
    CURRENT_OS = "linux"
else:
    CURRENT_OS = sys.platform


@dataclass(frozen=True)
class Step:
    command: str
    cwd: Path | None = None
    env: dict[str, str] = field(default_factory=dict)
    platforms: tuple[str, ...] = ()
    windows_command: str | None = None


@dataclass(frozen=True)
class Operation:
    steps: tuple[Step, ...] = ()
    dependencies: tuple[tuple[str, str], ...] = ()
    description: str = ""


class Runner:
    def __init__(
        self,
        operations: dict[str, dict[str, Operation]],
        suites: dict[str, dict[str, tuple[str, ...]]],
        *,
        dry_run: bool = False,
    ) -> None:
        self.operations = operations
        self.suites = suites
        self.dry_run = dry_run
        self._seen: set[tuple[str, str]] = set()

    def run(self, action: str, items: list[str]) -> None:
        if action not in self.operations:
            choices = ", ".join(sorted(self.operations))
            raise SystemExit(f"unknown action: {action}\nKnown actions: {choices}")
        expanded = self.expand_items(action, items)
        if not expanded:
            raise SystemExit(f"{action} requires at least one platform or suite")
        for target in expanded:
            self.run_operation(action, target)

    def expand_items(self, action: str, items: list[str]) -> list[str]:
        expanded: list[str] = []
        action_suites = self.suites.get(action, {})
        for item in items:
            if item.startswith("suite:"):
                suite = item.removeprefix("suite:")
                if suite not in action_suites:
                    choices = ", ".join(sorted(action_suites))
                    raise SystemExit(f"unknown {action} suite: {suite}\nKnown suites: {choices}")
                expanded.extend(self.expand_items(action, list(action_suites[suite])))
            elif item in self.operations[action]:
                expanded.append(item)
            elif item in action_suites:
                expanded.extend(self.expand_items(action, list(action_suites[item])))
            else:
                choices = ", ".join(sorted(set(action_suites) | set(self.operations[action])))
                raise SystemExit(f"unknown {action} target: {item}\nKnown targets: {choices}")
        return list(dict.fromkeys(expanded))

    def run_operation(self, action: str, target: str) -> None:
        key = (action, target)
        if key in self._seen:
            return
        operation = self.operations[action][target]
        for dependency_action, dependency_target in operation.dependencies:
            self.run_operation(dependency_action, dependency_target)
        self._seen.add(key)
        for step in operation.steps:
            self.run_step(action, target, step)

    def run_step(self, action: str, target: str, step: Step) -> None:
        if step.platforms and CURRENT_OS not in step.platforms:
            allowed = ", ".join(step.platforms)
            print(f"[{action}:{target}] skip on {CURRENT_OS}; supported on {allowed}")
            return
        cwd = REPO_ROOT if step.cwd is None else REPO_ROOT / step.cwd
        command = step.windows_command if CURRENT_OS == "windows" and step.windows_command else step.command
        if CURRENT_OS == "windows":
            command = rewrite_windows_python_command(command)
        print(f"[{action}:{target}] {command}")
        if self.dry_run:
            return
        env = os.environ.copy()
        env.update(step.env)
        if CURRENT_OS == "windows":
            add_windows_dev_environment(env)
            inline_env = {}
        else:
            command, inline_env = split_inline_env(command)
            env.update(inline_env)
        subprocess.run(command, cwd=cwd, env=env, shell=True, check=True)


def sh(path: str | Path) -> str:
    import shlex

    return shlex.quote(str(path))


def rewrite_windows_python_command(command: str) -> str:
    if command == "python3" or command.startswith("python3 "):
        return f"{quote_windows_arg(sys.executable)}{command.removeprefix('python3')}"
    return command


def quote_windows_arg(value: str) -> str:
    escaped = value.replace('"', '\\"')
    return f'"{escaped}"' if any(char.isspace() for char in value) else escaped


def add_windows_dev_environment(env: dict[str, str]) -> None:
    path_separator = os.pathsep
    existing_paths = env.get("PATH", "").split(path_separator)
    paths: list[Path] = [
        REPO_ROOT / ".dotnet-sdk",
        Path.home() / ".cargo" / "bin",
        Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Go" / "bin",
    ]
    node_root = REPO_ROOT / ".node"
    if node_root.exists():
        paths.extend(sorted(node_root.glob("node-v*-win-x64"), key=node_directory_version, reverse=True))

    dev_paths = []
    for path in paths:
        path_text = str(path)
        if path.exists() and path_text not in existing_paths and path_text not in dev_paths:
            dev_paths.append(path_text)
    existing_paths = dev_paths + existing_paths
    env["PATH"] = path_separator.join(existing_paths)
    env.setdefault("GOTOOLCHAIN", "go1.25.0")
    env.setdefault("PYTHONIOENCODING", "utf-8")


def node_directory_version(path: Path) -> tuple[int, ...]:
    match = re.match(r"node-v(\d+(?:\.\d+)*)-win-x64$", path.name)
    if not match:
        return (0,)
    return tuple(int(part) for part in match.group(1).split("."))


def split_inline_env(command: str) -> tuple[str, dict[str, str]]:
    assignment = re.compile(r"\s*([A-Za-z_][A-Za-z0-9_]*)=('[^']*'|\"[^\"]*\"|\S+)(?:\s+|$)")
    inline_env: dict[str, str] = {}
    position = 0
    while match := assignment.match(command, position):
        key = match.group(1)
        value_token = match.group(2)
        if "$(" in value_token or "`" in value_token:
            break
        try:
            value = shlex.split(value_token)[0]
        except (IndexError, ValueError):
            break
        inline_env[key] = value
        position = match.end()
    if position == 0:
        return command, {}
    return command[position:], inline_env
