# Go Fyne renderer notes

`exp-platform/go/fyne` is an experimental desktop renderer that loads the same bundle manifest/page/string-table contract as the SwiftUI, WebUI, TUI, and Gio surfaces. WGS Extract is used as a generic behavior check only; the renderer does not hard-code WGS-specific rows, commands, or settings.

## Scope

The prototype includes a Fyne app shell with localized bundle title/summary, RTL-aware sidebar placement, language selection, page navigation, setup execution, workspace opening, generated controls, config-editor loading/autosave, data-source hydration, library rows, action visibility/disabled checks, confirmations, terminal tabs, command status, and process-tree cancellation.

Terminal/log/path text remains LTR through standard Fyne entries. Icon-only actions are rendered with text labels when possible so custom controls have accessible names.

## Commands

```sh
make test PLATFORM=fyne
make build PLATFORM=fyne
make run PLATFORM=fyne BUNDLE=examples/WGSExtract
make package PLATFORM=fyne
make benchmark ARGS='fyne-macos'
```

The release target stages `out/release/fyne/gui-for-cli-fyne`, the default WGS Extract bundle, and built-in app string tables. The benchmark target reads `metric *_ms=` lines and writes `out/release/fyne/benchmark-macos.json`.

## Current limitations

Fyne does not expose an exact first-real-frame callback like Gio's frame event. The current metric is emitted after the window is configured and the initial UI has had a short render window; benchmark numbers should be treated as readiness data until a stricter hook is available. File dialogs use native Fyne dialogs but do not yet seed the picker location from the current valid path.
