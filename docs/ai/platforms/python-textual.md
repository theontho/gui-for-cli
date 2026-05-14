# Python renderer notes

`exp-platform/python/shared` is the shared Python runtime for experimental Python renderers. Textual, Tkinter, and wxPython load split bundle manifests, page JSON files, TOML string tables, and the same action/interpolation semantics used by the other surfaces without hard-coding WGS Extract behavior.

## Scope

The shared runtime covers archive/directory bundle loading, localization, workspace resolution, required-placeholder checks, command interpolation, script-backed data-source hydration, action visibility/enabled state, process-tree cancellation, and benchmark markers.

The Textual prototype has a terminal UI shell with localized bundle title, RTL-aware sidebar placement, generated controls, data-source refresh, action execution, terminal entries, process-tree cancellation, and benchmark markers. The Tkinter and wxPython prototypes add desktop app shells with sidebars, generated controls, terminal notebooks/tabs, cancel/close affordances, data-source refresh after commands, RTL sidebar placement, and `--once` smoke/benchmark modes that do not open a window.

Archive loading supports bundle directories, direct `manifest.json` files, one-top-level-directory archives, `.zip`, `.tar`, `.tar.gz`, `.tgz`, and single-manifest `.gz` inputs. Extracted archives and workspaces stay under repository `tmp/` paths during development.

## Commands

```sh
make setup-python
make setup-textual
make setup-tkinter
make setup-wx
make test-python
make test-textual
make run-textual BUNDLE=examples/WGSExtract
make run-tkinter BUNDLE=examples/WGSExtract
make run-wx BUNDLE=examples/WGSExtract
make textual BUNDLE=examples/WGSExtract
make benchmark-textual BUNDLE=examples/WGSExtract
make benchmark-tkinter BUNDLE=examples/WGSExtract
make benchmark-wx BUNDLE=examples/WGSExtract
```

`make test-python` runs the shared runtime tests, imports/compiles all Python renderer packages, and exercises Textual/Tkinter/wxPython `--once` smoke paths. wxPython itself is not required for `make test-python` because `gui_for_cli_wx --once` validates bundle/core rendering before importing `wx`.

`make benchmark-textual`, `make benchmark-tkinter`, and `make benchmark-wx` run the renderer entry points with `--benchmark --benchmark-full --once`, print `metric *_ms=` lines, and write JSON under `out/release/<renderer>/benchmark.json` by default.

## Current limitations

The benchmarks are headless bundle-load/core-render measurements, not first-frame callbacks from the UI frameworks. The interactive shells are functional but still lighter than the stable TypeScript TUI: row actions are represented in core state, while richer table action controls, confirmation prompts, setup orchestration, native path-picking equivalents, persisted non-config UI state, and polished native close buttons need more parity work before promotion from experimental status.
