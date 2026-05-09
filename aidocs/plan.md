# GUI for CLI — Continued Plan

## Current status
- Core Swift package, CLI, macOS app, and WebUI are in place.
- CI and local quality checks (`make lint`, `make test`, `make build-cli`) are already wired.

## Next steps
1. Stabilize cross-platform test behavior (Windows/macOS differences around script executability).
2. Keep CLI subcommands (`precheck`, `config`, `run`, `bundle setup`) aligned with shared core behavior.
3. Continue improving app/WebUI parity for bundle rendering and setup workflows.
4. Expand smoke-style validation for accessibility and localized UI content.
