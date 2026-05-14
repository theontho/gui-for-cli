from __future__ import annotations

import argparse
import locale as system_locale
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

from . import __version__


@dataclass(frozen=True)
class TextualArgs:
    repo_root: Path
    bundle: Path
    locale: str
    theme: str
    benchmark: bool
    benchmark_full: bool
    once: bool
    no_setup: bool
    benchmark_output: Path | None


def parse_args(argv: Sequence[str] | None = None, env: dict[str, str] | None = None) -> TextualArgs:
    env = env or os.environ
    parser = argparse.ArgumentParser(description="GUI for CLI experimental Python Textual renderer")
    parser.add_argument("--repo-root", default=env.get("GFC_TEXTUAL_REPO_ROOT"))
    parser.add_argument("--bundle", default=env.get("GFC_TEXTUAL_BUNDLE"))
    parser.add_argument("--locale", default=env.get("GFC_TEXTUAL_LOCALE"))
    parser.add_argument("--theme", choices=("auto", "dark", "light"), default=env.get("GFC_TEXTUAL_THEME", "auto"))
    parser.add_argument("--benchmark", action="store_true")
    parser.add_argument("--benchmark-full", action="store_true")
    parser.add_argument("--once", action="store_true", help="Load, render core state, print benchmark markers, and exit")
    parser.add_argument("--no-setup", action="store_true", help="Do not run setup automatically")
    parser.add_argument("--benchmark-output")
    parser.add_argument("--version", "-V", action="version", version=f"gui-for-cli-textual {__version__}")
    ns = parser.parse_args(argv)

    repo_root = Path(ns.repo_root).expanduser().resolve() if ns.repo_root else find_repo_root(Path.cwd())
    bundle = Path(ns.bundle).expanduser() if ns.bundle else repo_root / "examples" / "WGSExtract"
    if not bundle.is_absolute():
        bundle = (repo_root / bundle).resolve()
    else:
        bundle = bundle.resolve()
    benchmark_output = Path(ns.benchmark_output).expanduser().resolve() if ns.benchmark_output else None
    return TextualArgs(
        repo_root=repo_root,
        bundle=bundle,
        locale=normalize_locale(ns.locale or detected_locale()),
        theme=ns.theme,
        benchmark=bool(ns.benchmark or ns.benchmark_full),
        benchmark_full=bool(ns.benchmark_full),
        once=bool(ns.once),
        no_setup=bool(ns.no_setup),
        benchmark_output=benchmark_output,
    )


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
