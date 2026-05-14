# Rust Xilem/Vello renderer experiment

`exp-platform/rust/xilem-vello` is the Rust Xilem/Vello experiment. The current implementation deliberately ships as a compiled headless/core renderer: it loads bundles through `exp-platform/rust/shared`, validates localization and metadata, warms controls/data sources for benchmarks, and exposes `--check`, `--benchmark`, `--benchmark-full`, `--once`, and `--benchmark-output`.

## Current status

- Bundle/runtime behavior is shared with the other Rust prototypes: workspace preparation, localization, state/config writes, data-source caching, action conditions/interpolation, process execution, terminal state, and benchmark summaries.
- The native Xilem/Vello window is not wired yet. Xilem `0.4` and Vello `0.6` are still moving quickly, and their app/window examples are not stable enough for a maintainable renderer shell in this repo. There are no non-compiling Xilem UI references left in the package.
- `make run-xilem-vello` runs the core once and emits the same benchmark marker used by `--once`; it is a readiness/runtime smoke test, not a visual UI.

## Commands

```sh
make test-xilem-vello
make build-xilem-vello
make run-xilem-vello BUNDLE=examples/WGSExtract
make benchmark-xilem-vello BUNDLE=examples/WGSExtract
```

Direct Cargo/CLI equivalents:

```sh
cargo test --manifest-path exp-platform/rust/xilem-vello/Cargo.toml
cargo check --manifest-path exp-platform/rust/xilem-vello/Cargo.toml
cargo build --manifest-path exp-platform/rust/xilem-vello/Cargo.toml --release
GUI_FOR_CLI_OFFLINE=1 GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT="$PWD/tmp/xilem-vello-workspaces" \
  exp-platform/rust/xilem-vello/target/release/gui-for-cli-xilem-vello \
  --bundle examples/WGSExtract \
  --benchmark \
  --benchmark-full \
  --once
```

## Benchmark marker

The headless marker uses `first_render_marker=headless-core-ready` and `ui_blocker=xilem-api-pending` so benchmark consumers do not mistake it for a visual first-frame measurement.
