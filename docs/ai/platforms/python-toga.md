# Python Toga/BeeWare renderer

The Python Toga/BeeWare renderer lives at `exp-platform/python/toga`. It is an experimental desktop surface that loads the same GUI-for-CLI bundle layout as the SwiftUI/WebUI/TUI implementations and keeps its portable runtime behavior testable without opening a native window.

## Commands

```bash
make test PLATFORM=toga
make run PLATFORM=toga BUNDLE=examples/WGSExtract
BUNDLE=examples/WGSExtract make benchmark ARGS='toga'
```

Useful direct non-window checks:

```bash
PYTHONPATH=exp-platform/python/toga/src python3 -m gui_for_cli_toga \
  --repo-root "$PWD" --bundle examples/WGSExtract --workspace-root "$PWD/tmp/python-toga-workspace" --describe

PYTHONPATH=exp-platform/python/toga/src GUI_FOR_CLI_OFFLINE=1 python3 -m gui_for_cli_toga \
  --repo-root "$PWD" --bundle examples/WGSExtract --workspace-root "$PWD/tmp/python-toga-workspace" \
  --benchmark --benchmark-full --once --benchmark-output out/python-toga/benchmark.txt
```

Install the package (`python3 -m pip install -e exp-platform/python/toga`) when launching the Toga UI, because fast non-window tests intentionally avoid importing `toga`.

## Current coverage

Non-window tests cover bundle loading, localization and RTL detection, missing localization keys rendering as keys, required-placeholder action disabling, disabled/hidden action conditions, command interpolation and optional arguments, config save/load, render snapshots, CLI `--describe`, and benchmark/`--once` markers. `make benchmark ARGS='toga'` launches the real Toga window and measures `ui_ready_ms`.

## Remaining gaps

The UI shell is still a prototype: terminal tabs, process status affordances, setup execution, path pickers, precheck dialogs, and richer native accessibility semantics need parity work before this can graduate from `exp-platform`.
