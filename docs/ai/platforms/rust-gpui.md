# Rust GPUI renderer notes

`exp-platform/rust/gpui` is the Rust GPUI renderer experiment. It loads the shared Rust renderer model and opens a native GPUI window for normal and benchmark runs.

## Current behavior

- Reuses `exp-platform/rust/shared` for WGS bundle loading, workspace preparation, localization, state/config behavior, data-source/action conditions, command interpolation, terminal state, and benchmark output.
- Supports `--check` to print a bundle summary.
- Supports `--benchmark`, `--benchmark-full`, `--once`, and `--benchmark-output`; benchmark mode emits a real window-surface `ui_ready_ms` marker.
- A plain run opens the GPUI window with bundle title, summary, page list, current page controls/actions, and a simple page navigation affordance.

## Commands

```sh
make test-gpui
make build-gpui
make run-gpui BUNDLE=examples/WGSExtract
BUNDLE=examples/WGSExtract make benchmark ARGS='benchmark gpui'
```

Direct Cargo validation:

```sh
cargo check --manifest-path exp-platform/rust/gpui/Cargo.toml
cargo run --manifest-path exp-platform/rust/gpui/Cargo.toml -- --bundle examples/WGSExtract --check
cargo run --manifest-path exp-platform/rust/gpui/Cargo.toml -- --bundle examples/WGSExtract --benchmark --benchmark-full
```

## Toolchain note

The published `gpui = "0.2.2"` crate requires Apple's Metal toolchain on macOS. If its build script fails with `metal shader compilation failed`, install that Xcode component with `xcodebuild -downloadComponent MetalToolchain`.
