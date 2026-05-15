# Rust Xilem/Vello renderer experiment

`exp-platform/rust/xilem-vello` is the Rust Xilem/Vello experiment. It loads bundles through `exp-platform/rust/shared`, renders a native Xilem/Vello window for normal and benchmark runs, validates localization and metadata, warms controls/data sources for benchmarks, and exposes `--check`, `--benchmark`, `--benchmark-full`, `--once`, and `--benchmark-output`.

## Current status

- Bundle/runtime behavior is shared with the other Rust prototypes: workspace preparation, localization, state/config writes, data-source caching, action conditions/interpolation, process execution, terminal state, and benchmark summaries.
- The native Xilem/Vello window renders bundle title, summary, page navigation, current page state, and benchmark-ready markers.
- `make run-xilem-vello` opens the window. `--once` remains available for fast core smoke tests only.

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
  --benchmark-output out/release/xilem-vello/benchmark.txt
```

## Benchmark marker

The window benchmark prints `metric ui_ready_ms=...` after the Xilem app logic builds the first surface view. The generic macOS process harness waits for that marker and then samples RSS before terminating the benchmark process.
