# Python renderer notes

`exp-platform/python/shared` is the shared Python runtime for experimental Python renderers. Textual, Tkinter, and wxPython load split bundle manifests, page JSON files, TOML string tables, and the same action/interpolation semantics used by the other surfaces without hard-coding WGS Extract behavior.

## Scope

The shared runtime covers archive/directory bundle loading, localization, workspace resolution, required-placeholder checks, command interpolation, script-backed data-source hydration, action visibility/enabled state, process-tree cancellation, and benchmark markers.

The Textual prototype has a terminal UI shell with localized bundle title, RTL-aware sidebar placement, generated controls, data-source refresh, action execution, terminal entries, process-tree cancellation, and benchmark markers. The Tkinter and wxPython prototypes add desktop app shells with sidebars, generated controls, terminal notebooks/tabs, cancel/close affordances, data-source refresh after commands, RTL sidebar placement, and `--once` smoke modes that do not open a window.

Archive loading supports bundle directories, direct `manifest.json` files, one-top-level-directory archives, `.zip`, `.tar`, `.tar.gz`, `.tgz`, and single-manifest `.gz` inputs. Extracted archives and workspaces stay under repository `tmp/` paths during development.

## Commands

```sh
make setup SUITE=python
make setup PLATFORM=textual
make setup PLATFORM=tkinter
make setup PLATFORM=wx
make test PLATFORM=python
make test PLATFORM=textual
make run PLATFORM=textual BUNDLE=examples/WGSExtract
make run PLATFORM=tkinter BUNDLE=examples/WGSExtract
make run PLATFORM=wx BUNDLE=examples/WGSExtract
make textual BUNDLE=examples/WGSExtract
BUNDLE=examples/WGSExtract make benchmark ARGS='textual'
BUNDLE=examples/WGSExtract make benchmark ARGS='tkinter'
BUNDLE=examples/WGSExtract make benchmark ARGS='wx'
```

`make test PLATFORM=python` runs the shared runtime tests, imports/compiles all Python renderer packages, and exercises Textual/Tkinter/wxPython `--once` smoke paths. wxPython itself is not required for `make test PLATFORM=python` because `gui_for_cli_wx --once` validates bundle/core rendering before importing `wx`.

`make benchmark ARGS='textual'`, `make benchmark ARGS='tkinter'`, and `make benchmark ARGS='wx'` launch the real terminal/window surface with `--benchmark --benchmark-full`, wait for `ui_ready_ms`, sample RSS, and write JSON under `out/release/<renderer>/benchmark.json` by default.

## Current limitations

The benchmarks now exercise real terminal/window surfaces. The interactive shells are still lighter than the stable TypeScript TUI: row actions are represented in core state, while richer table action controls, confirmation prompts, setup orchestration, native path-picking equivalents, persisted non-config UI state, and polished native close buttons need more parity work before promotion from experimental status.
