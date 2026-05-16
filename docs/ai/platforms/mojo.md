# Mojo headless/core renderer

`exp-platform/mojo` is a Mojo experiment that mirrors the shared Python renderer runtime in a compiled headless/core surface. It uses Pixi to install Mojo from the Modular channel and currently focuses on bundle loading, localization, interpolation, action state, row hydration, archive extraction, describe output, and benchmark markers.

## Commands

```bash
make setup-mojo
make test-mojo
make build-mojo
make run-mojo BUNDLE=examples/WGSExtract
BUNDLE=examples/WGSExtract make benchmark ARGS='benchmark mojo-core'
```

Useful direct checks:

```bash
cd exp-platform/mojo
pixi run mojo run src/gui_for_cli_mojo.mojo --repo-root ../.. --bundle examples/WGSExtract --describe
pixi run mojo run src/gui_for_cli_mojo.mojo --repo-root ../.. --bundle examples/WGSExtract --benchmark --benchmark-full --once
```

## Current limitations

This is not a native GUI renderer yet. Mojo does not currently provide a mature cross-platform desktop UI toolkit in this repository, so the first version validates the portable runtime/render model and benchmark path that a future Mojo UI shell would consume.
