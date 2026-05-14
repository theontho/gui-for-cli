from __future__ import annotations

import argparse
import json
import locale as system_locale
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

from .bundle import load_bundle
from .state import RuntimeState, build_core_state


@dataclass(frozen=True)
class RuntimeArgs:
    repo_root: Path
    bundle: Path
    locale: str
    benchmark: bool
    benchmark_full: bool
    once: bool
    no_setup: bool
    benchmark_output: Path | None


def parse_runtime_args(
    argv: Sequence[str] | None = None,
    *,
    description: str,
    env_prefix: str,
    version: str,
    env: dict[str, str] | None = None,
) -> RuntimeArgs:
    env = env or os.environ
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("--repo-root", default=env.get(f"{env_prefix}_REPO_ROOT"))
    parser.add_argument("--bundle", default=env.get(f"{env_prefix}_BUNDLE"))
    parser.add_argument("--locale", default=env.get(f"{env_prefix}_LOCALE"))
    parser.add_argument("--benchmark", action="store_true")
    parser.add_argument("--benchmark-full", action="store_true")
    parser.add_argument("--once", action="store_true", help="Load, render core state, print benchmark markers, and exit")
    parser.add_argument("--no-setup", action="store_true", help="Do not run setup automatically")
    parser.add_argument("--benchmark-output")
    parser.add_argument("--version", "-V", action="version", version=version)
    ns = parser.parse_args(argv)

    repo_root = Path(ns.repo_root).expanduser().resolve() if ns.repo_root else find_repo_root(Path.cwd())
    bundle = Path(ns.bundle).expanduser() if ns.bundle else repo_root / "examples" / "WGSExtract"
    bundle = (repo_root / bundle).resolve() if not bundle.is_absolute() else bundle.resolve()
    benchmark_output = Path(ns.benchmark_output).expanduser().resolve() if ns.benchmark_output else None
    return RuntimeArgs(
        repo_root=repo_root,
        bundle=bundle,
        locale=normalize_locale(ns.locale or detected_locale()),
        benchmark=bool(ns.benchmark or ns.benchmark_full),
        benchmark_full=bool(ns.benchmark_full),
        once=bool(ns.once),
        no_setup=bool(ns.no_setup),
        benchmark_output=benchmark_output,
    )


def load_core_runtime(args: RuntimeArgs):
    started = time.perf_counter()
    bundle = load_bundle(args.bundle, args.repo_root, args.locale)
    loaded = time.perf_counter()
    state = RuntimeState.for_bundle(bundle)
    core = build_core_state(bundle, state)
    ready = time.perf_counter()
    metrics = {
        "bundleLoaded_ms": round((loaded - started) * 1000, 3),
        "uiReady_ms": round((ready - started) * 1000, 3),
        "pages": len(core.pages),
        "actions": core.action_count,
        "controls": core.control_count,
    }
    return bundle, state, core, metrics


def emit_metrics(metrics: dict[str, object], benchmark_output: Path | None = None) -> None:
    for key, value in metrics.items():
        print(f"metric {key}={value}")
    if benchmark_output:
        benchmark_output.parent.mkdir(parents=True, exist_ok=True)
        benchmark_output.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")


def find_repo_root(start: Path) -> Path:
    for candidate in [start.resolve(), *start.resolve().parents]:
        if (candidate / ".git").exists() and (candidate / "examples").is_dir():
            return candidate
    return start.resolve()


def detected_locale() -> str:
    raw = system_locale.getlocale()[0] or os.environ.get("LANG") or "en"
    return raw.split(".", 1)[0]


def normalize_locale(value: str) -> str:
    normalized = value.replace("_", "-").strip()
    return normalized or "en"
