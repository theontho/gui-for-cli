# Rust GPUI renderer notes

`exp-platform/rust/gpui` is the Rust GPUI renderer experiment. In this worktree it is a compiled headless/core runner instead of a windowed GPUI app because the published `gpui` crate currently fails its Metal shader build on macOS before the app code can compile.

## Current behavior

- Reuses `exp-platform/rust/shared` for WGS bundle loading, workspace preparation, localization, state/config behavior, data-source/action conditions, command interpolation, terminal state, and benchmark output.
- Supports `--check` to print a bundle summary.
- Supports `--benchmark`, `--benchmark-full`, `--once`, and `--benchmark-output` for CI and startup-core measurements.
- A plain run prints the GPUI UI blocker and a check summary, then exits successfully.

## Commands

```sh
make test-gpui
make build-gpui
make run-gpui BUNDLE=examples/WGSExtract
make benchmark-gpui BUNDLE=examples/WGSExtract
```

Direct Cargo validation:

```sh
cargo check --manifest-path exp-platform/rust/gpui/Cargo.toml
cargo run --manifest-path exp-platform/rust/gpui/Cargo.toml -- --bundle examples/WGSExtract --check
cargo run --manifest-path exp-platform/rust/gpui/Cargo.toml -- --bundle examples/WGSExtract --benchmark --benchmark-full --once
```

## UI blocker

The first attempted implementation depended on `gpui = "0.2.2"`, but `cargo test --manifest-path exp-platform/rust/gpui/Cargo.toml` failed inside the GPUI build script with `metal shader compilation failed`. The current package removes that dependency so shared runtime work remains buildable and testable while a compatible GPUI version or shader-toolchain fix is investigated.
