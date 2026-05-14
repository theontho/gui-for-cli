# Python Textual renderer notes

`exp-platform/python/textual` is an experimental terminal UI renderer for GUI for CLI bundles. It loads split bundle manifests, page JSON files, TOML string tables, and the same action/interpolation semantics used by the other surfaces without hard-coding WGS Extract behavior.

## Scope

The prototype has a Textual app shell with localized bundle title, RTL-aware sidebar placement, generated controls, script-backed data-source hydration, action visibility/disabled checks, terminal entries, process-tree cancellation, and benchmark markers. Bundle loading, localization, required placeholders, command interpolation, and core render state are covered by headless tests that do not open a Textual UI.

Archive loading supports bundle directories, direct `manifest.json` files, one-top-level-directory archives, `.zip`, `.tar`, `.tar.gz`, `.tgz`, and single-manifest `.gz` inputs. Extracted archives and workspaces stay under repository `tmp/` paths during development.

## Commands

```sh
make setup-textual
make test-textual
make run-textual BUNDLE=examples/WGSExtract
make textual BUNDLE=examples/WGSExtract
make benchmark-textual BUNDLE=examples/WGSExtract
```

`make test-textual` uses Python `unittest` with `PYTHONPATH=exp-platform/python/textual` and includes an import/version smoke check. `make benchmark-textual` runs the renderer with `--benchmark --benchmark-full --once`, prints `metric *_ms=` lines, and writes `out/release/textual/benchmark.json` by default.

## Current limitations

The benchmark is a headless bundle-load/core-render measurement, not a first-terminal-frame callback from Textual. The interactive shell is functional but still lighter than the stable TypeScript TUI: row actions are represented in core state, while richer table action controls, confirmation prompts, setup orchestration, native path-picking equivalents, and persisted non-config UI state need more parity work before promotion from experimental status.
