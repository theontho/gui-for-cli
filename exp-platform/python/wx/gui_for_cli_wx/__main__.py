from __future__ import annotations

import sys
import time

from gui_for_cli_runtime.cli import emit_metrics, load_core_runtime, parse_runtime_args

from . import __version__


def main(argv: list[str] | None = None) -> int:
    started = time.perf_counter()
    args = parse_runtime_args(
        argv,
        description="GUI for CLI experimental Python wxPython renderer",
        env_prefix="GFC_WX",
        version=f"gui-for-cli-wx {__version__}",
    )
    bundle, state, _core, metrics = load_core_runtime(args)
    if args.once:
        emit_metrics(metrics, args.benchmark_output)
    if args.once:
        return 0

    try:
        from .app import WxRendererApp
    except ModuleNotFoundError as exc:
        if exc.name == "wx":
            print("wxPython is not installed. Run `python3 -m pip install -e exp-platform/python/wx[ui]`.", file=sys.stderr)
            return 2
        raise
    app = WxRendererApp(
        bundle,
        state,
        benchmark_started=started if args.benchmark else None,
        benchmark_output=args.benchmark_output,
        core_metrics={**metrics, "coreReady_ms": metrics.get("uiReady_ms")},
    )
    app.MainLoop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
