"""Shared helpers for the benchmark CLI."""

from __future__ import annotations

import os
import shlex
import shutil
import subprocess
import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Suite:
    description: str
    items: tuple[str, ...]


@dataclass(frozen=True)
class BenchmarkCommand:
    description: str
    run: Callable[["Context"], None]


@dataclass(frozen=True)
class Context:
    env: dict[str, str]
    samples: int
    release_dir: Path
    bundle_root: Path
    headless_browser: bool
    capture_only: str | None
    no_focus: bool
    dry_run: bool

    @property
    def textual_python(self) -> str:
        return self.env.get("TEXTUAL_PYTHON", "python3")

    @property
    def derived_data_path(self) -> Path:
        return repo_path(self.env.get("DERIVED_DATA_PATH", "platform/apple/DerivedData"))

    @property
    def launch_args(self) -> list[str]:
        return shlex.split(self.env.get("LAUNCH_ARGS", ""))


def repo_path(*parts: str | Path) -> Path:
    if len(parts) == 1 and Path(parts[0]).is_absolute():
        return Path(parts[0])
    return REPO.joinpath(*map(str, parts))


def run(ctx: Context, command: list[str], *, cwd: Path = REPO, env: dict[str, str] | None = None) -> None:
    if ctx.dry_run:
        prefix = f"cd {shlex.quote(str(cwd))} && " if cwd != REPO else ""
        env_prefix = " ".join(f"{key}={shlex.quote(value)}" for key, value in sorted((env or {}).items()))
        print(f"{prefix}{env_prefix + ' ' if env_prefix else ''}{shlex.join(command)}")
        return
    merged_env = ctx.env.copy()
    if env:
        merged_env.update(env)
    subprocess.run(command, cwd=cwd, env=merged_env, check=True)


def platform(ctx: Context, action: str, target: str) -> None:
    run(ctx, [sys.executable, "tools/platform.py", action, target])


def mkdir(ctx: Context, *paths: Path) -> None:
    for path in paths:
        if ctx.dry_run:
            print(f"mkdir -p {shlex.quote(str(path))}")
        else:
            path.mkdir(parents=True, exist_ok=True)


def remove_tree(ctx: Context, path: Path) -> None:
    if ctx.dry_run:
        print(f"rm -rf {shlex.quote(str(path))}")
    else:
        shutil.rmtree(path, ignore_errors=True)


def remove_files(ctx: Context, cwd: Path, names: list[str]) -> None:
    if ctx.dry_run:
        print(f"cd {shlex.quote(str(cwd))} && rm -f {' '.join(map(shlex.quote, names))}")
        return
    for name in names:
        try:
            (cwd / name).unlink()
        except FileNotFoundError:
            pass


def macos_process(
    ctx: Context,
    *,
    name: str,
    ready_metric: str,
    output: Path,
    artifacts: list[Path],
    command: list[str],
    timeout: int | None = None,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> None:
    process_command = [sys.executable, "tools/benchmarking/macos_process.py"]
    if ctx.no_focus:
        process_command.append("--preserve-focus")
    process_command.extend(["--name", name, "--samples", str(ctx.samples), "--ready-metric", ready_metric, "--output", str(output)])
    if timeout is not None:
        process_command.extend(["--timeout", str(timeout)])
    for artifact in artifacts:
        process_command.extend(["--artifact", str(artifact)])
    if cwd is not None:
        process_command.extend(["--cwd", str(cwd)])
    for key, value in (env or {}).items():
        process_command.extend(["--env", f"{key}={value}"])
    process_command.extend(["--", *command])
    run(ctx, process_command)


def kotlin_env(ctx: Context) -> dict[str, str]:
    env: dict[str, str] = {}
    java_home = ctx.env.get("KOTLIN_JAVA_HOME")
    if java_home is None:
        default_java = Path("/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home")
        if default_java.exists():
            java_home = str(default_java)
    android_home = ctx.env.get("KOTLIN_ANDROID_HOME")
    if android_home is None:
        default_android = Path.home() / "Library/Android/sdk"
        if default_android.exists():
            android_home = str(default_android)
    if java_home:
        env["JAVA_HOME"] = java_home
    if android_home:
        env["ANDROID_HOME"] = android_home
        env["ANDROID_SDK_ROOT"] = android_home
    return env


def context_from_args(args: object) -> Context:
    env = os.environ.copy()
    samples = getattr(args, "samples", None) if getattr(args, "samples", None) is not None else int(env.get("SAMPLES", "7"))
    if samples < 1:
        raise SystemExit("--samples must be >= 1")
    if getattr(args, "no_focus", False):
        env["GFC_BENCHMARK_PRESERVE_FOCUS"] = "1"
    return Context(
        env=env,
        samples=samples,
        release_dir=repo_path(env.get("RELEASE_DIR", "out/release")),
        bundle_root=repo_path(env.get("BUNDLE", env.get("DEFAULT_BUNDLE", "examples/WGSExtract"))).resolve(),
        headless_browser=getattr(args, "headless_browser", False) or env.get("HEADLESS") == "1",
        capture_only=getattr(args, "capture_only", None) or env.get("CAPTURE_ONLY"),
        no_focus=getattr(args, "no_focus", False) or env.get("GFC_BENCHMARK_PRESERVE_FOCUS") == "1" or env.get("NO_FOCUS") == "1",
        dry_run=getattr(args, "dry_run", False),
    )
