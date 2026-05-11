# Agent history behavior spec

This spec captures the recurring implementation requirements that have come up while building `gui-for-cli`. It is intentionally practical: future agents should use it as a checklist before claiming a UI shell, runtime, or benchmark task is complete.

## Requirements

1. Match behavior across app surfaces. Experimental shells should not stop at a visual scaffold; they need the same meaningful bundle-driven capabilities as the SwiftUI and WebUI versions: navigation, setup, standard preferences, controls, config editing, library rows/actions, action prechecks, confirmations, data-source retry, terminal output, and benchmark coverage.
2. Preserve bundle and workspace semantics. The bundle manifest, localized labels, persisted bundle state, config files, workspace paths, and setup flow are the source of truth. Do not invent a parallel app-specific state model when existing core/WebUI APIs can be reused.
3. Treat terminal/process behavior as real app behavior. Commands must expose the rendered command, output, exit status, process errors, cancellation where supported, and clear failure states. Do not replace failed work with success-shaped fallbacks.
4. Keep localization, RTL, and accessibility visible in the implementation. UI text should flow through labels/manifests where available, right-to-left layout/text direction should be honored, and interactive controls need accessible roles/labels/hints.
5. Avoid backward-compatibility shims while the project is greenfield. When changing schemas or behavior, update all call sites and tests instead of leaving legacy paths.
6. Avoid megafiles. Large files should be split around obvious responsibilities so future agents can reason about them safely.
7. Validate realistically. Run the relevant lint/build/test/benchmark commands, and for app work include launch or render-benchmark coverage that exercises the full-featured surface rather than a toy fixture.

## React Native parity checklist

For the React Native experimental app in this PR branch, conformance means:

- The app renders the same full-featured bundle surface as SwiftUI/WebUI where React Native can reasonably support it.
- Backend access stays explicit through the WebUI API server; React Native should not duplicate command/config/path-picker implementations.
- Terminal tabs support command status, cancellation, closing, and text direction.
- Setup, preferences, config load/save, path picking, data-source retry, prechecks, and confirmations are wired into the visible UI.
- Benchmark fixtures include the richer shell, setup, settings, grouped controls, terminal tabs, confirmations, and action variants.
- Source files remain split by responsibility as the feature grows.
