from __future__ import annotations

from pathlib import Path
import argparse
import json
import sys
from time import perf_counter

from .benchmark import run_benchmark
from .bundle_loader import find_repo_root, load_bundle
from .runtime import RuntimeModel


def build_parser() -> argparse.ArgumentParser:
    repo = find_repo_root(Path.cwd())
    parser = argparse.ArgumentParser(description="Run the experimental Python Toga GUI for CLI renderer.")
    parser.add_argument("--bundle", default=str(repo / "examples" / "WGSExtract"), help="Bundle directory or archive")
    parser.add_argument("--repo-root", default=str(repo), help="Repository root containing resources/")
    parser.add_argument("--locale", help="Localization code, e.g. en, ar, zh-Hans")
    parser.add_argument("--workspace-root", default=None, help="Writable bundle workspace root")
    parser.add_argument("--benchmark", action="store_true", help="Print startup/render benchmark markers")
    parser.add_argument("--benchmark-full", action="store_true", help="Refresh data sources before benchmark completion")
    parser.add_argument("--benchmark-output", default=None, help="Write benchmark marker to a file outside /tmp")
    parser.add_argument("--once", action="store_true", help="Load and render state once without opening the UI")
    parser.add_argument("--describe", action="store_true", help="Print a headless render-state summary")
    return parser


def main(argv: list[str] | None = None) -> int:
    started = perf_counter()
    args = build_parser().parse_args(argv)
    if args.once:
        try:
            print(run_benchmark(
                args.bundle,
                repo_root=args.repo_root,
                locale=args.locale,
                output=args.benchmark_output,
                full=args.benchmark_full,
                workspace_root=args.workspace_root,
            ))
        except Exception as error:
            print(f"toga benchmark failed: {error}", file=sys.stderr)
            return 1
        return 0
    bundle = load_bundle(args.bundle, repo_root=args.repo_root, locale=args.locale, workspace_root=args.workspace_root)
    model = RuntimeModel(bundle)
    model.bootstrap()
    if args.benchmark_full:
        model.refresh_all_data_sources()
    if args.describe:
        print(json.dumps(model.render_snapshot(), sort_keys=True))
        return 0
    try:
        from .ui.app import run_app
    except ImportError as error:
        print(f"Toga UI is unavailable: {error}. Install with `python3 -m pip install -e exp-platform/python/toga`.", file=sys.stderr)
        return 2
    run_app(
        model,
        benchmark_started=started if args.benchmark else None,
        benchmark_output=Path(args.benchmark_output).expanduser().resolve() if args.benchmark_output else None,
    )
    return 0
