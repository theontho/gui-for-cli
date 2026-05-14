from __future__ import annotations

import json
import sys
import time

from .args import parse_args
from gui_for_cli_runtime.bundle import load_bundle
from gui_for_cli_runtime.state import RuntimeState, build_core_state


def main(argv: list[str] | None = None) -> int:
    started = time.perf_counter()
    args = parse_args(argv)
    bundle = load_bundle(args.bundle, args.repo_root, args.locale)
    loaded = time.perf_counter()
    state = RuntimeState.for_bundle(bundle)
    core = build_core_state(bundle, state)
    ready = time.perf_counter()

    if args.benchmark or args.once:
        metrics = {
            "bundleLoaded_ms": round((loaded - started) * 1000, 3),
            "uiReady_ms": round((ready - started) * 1000, 3),
            "pages": len(core.pages),
            "actions": core.action_count,
            "controls": core.control_count,
        }
        for key, value in metrics.items():
            print(f"metric {key}={value}")
        if args.benchmark_output:
            args.benchmark_output.parent.mkdir(parents=True, exist_ok=True)
            args.benchmark_output.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
    if args.once:
        return 0

    try:
        from .ui.app import GUIForCLITextualApp
    except ModuleNotFoundError as exc:
        if exc.name == "textual":
            print("Python Textual is not installed. Run `python3 -m pip install -e exp-platform/python/textual`.", file=sys.stderr)
            return 2
        raise
    app = GUIForCLITextualApp(bundle, state, args)
    app.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
