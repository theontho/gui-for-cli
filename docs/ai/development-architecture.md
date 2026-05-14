# Development architecture

This repository is organized by stable platform surfaces and experimental prototypes.

## Stable platform code

| Path | Purpose |
| --- | --- |
| `platform/apple/swiftui` | Stable SwiftUI macOS app entry point. |
| `platform/apple/shared/app` | Shared SwiftUI app views, resources, renderers, and terminal UI components. |
| `platform/apple/shared/Sources/GUIForCLICore` | Reusable Swift bundle/config/render/setup/state logic. |
| `platform/apple/shared/Sources/GUIForCLICLI` | Swift CLI parsing and terminal output. |
| `platform/apple/shared/Tests` | Swift package tests. |
| `platform/apple/Package.swift` | SwiftPM package manifest for the Apple/shared Swift code. |
| `platform/apple/shared/Package.swift` | Local SwiftPM manifest exposing only `GUIForCLICore` to Tuist app targets without resolving CLI-only dependencies. |
| `platform/apple/Project.swift` and `platform/apple/Tuist.swift` | Tuist manifests that generate the Apple Xcode workspace under `platform/apple`. |
| `platform/typescript/web/src/client` | Browser-side Web UI TypeScript. |
| `platform/typescript/web/src/server` | Local Node HTTP backend for bundle loading, process execution, data sources, and file/config access. |
| `platform/typescript/web/packagers` | Web UI desktop packagers: WKWebView shell, Tauri, and Electron. |
| `platform/typescript/tui` | Stable TypeScript terminal UI. |
| `platform/typescript/shared` | Isomorphic TypeScript model/rendering/localization helpers shared by browser, server, TUI, and packagers. |

## Experimental code

| Path | Purpose |
| --- | --- |
| `platform/apple/exp/ios-swiftui` | SwiftUI iOS experiment. |
| `platform/apple/exp/swift-appkit` | Swift AppKit experiment. |
| `platform/apple/exp/objc-appkit` | Objective-C AppKit experiment. |
| `exp-platform/rust/shared` | Shared Rust bundle/runtime helpers for Rust prototypes. |
| `exp-platform/rust/dioxus-shell` | Dioxus Web UI shell experiment. |
| `exp-platform/rust/gtk4` | GTK4/libadwaita native Rust renderer experiment. |
| `exp-platform/rust/slint` | Slint renderer experiment. |
| `exp-platform/rust/imgui` | Rust Dear ImGui renderer experiment. |
| `exp-platform/rust/iced` | Rust Iced renderer experiment using shared Rust bundle/runtime helpers. |
| `exp-platform/rust/egui` | Rust eframe/egui renderer experiment. |
| `exp-platform/rust/xilem-vello` | Rust Xilem/Vello headless core renderer experiment using shared Rust bundle/runtime helpers while native Xilem UI wiring is blocked on moving APIs. |
| `exp-platform/rust/gpui` | Rust GPUI renderer experiment; currently a headless/core runner that reuses shared Rust bundle/runtime helpers while the GPUI UI dependency is blocked. |
| `exp-platform/rust/raygui` | Rust Raygui renderer experiment. |
| `exp-platform/rust/makepad` | Rust Makepad desktop renderer experiment. |
| `exp-platform/dart/flutter` | Flutter renderer experiment. |
| `exp-platform/kotlin/compose/shared` | Shared Kotlin runtime and Compose UI for Kotlin renderer experiments. |
| `exp-platform/kotlin/compose/androidApp` | Jetpack Compose Android renderer experiment. |
| `exp-platform/kotlin/compose/desktopApp` | Compose Multiplatform desktop renderer experiment. |
| `exp-platform/cpp/imgui-cpp` | C++ Dear ImGui renderer experiment. |
| `exp-platform/cpp/qt-qml` | Qt 6/QML renderer experiment with a C++ runtime bridge and QML app shell. |
| `exp-platform/go/gio` | Go Gio renderer experiment. |
| `exp-platform/dotnet/avalonia` | Cross-platform Avalonia/.NET renderer experiment reusing the C# bundle runtime core. |
| `exp-platform/go/fyne` | Go Fyne desktop renderer experiment. |
| `exp-platform/python/shared` | Shared Python bundle/runtime helpers for Python renderer experiments. |
| `exp-platform/python/textual` | Python Textual terminal UI renderer experiment with bundle/runtime helpers, headless tests, and benchmark mode. |
| `exp-platform/python/tkinter` | Python Tkinter desktop renderer experiment using the shared Python runtime. |
| `exp-platform/python/wx` | Python wxPython desktop renderer experiment using the shared Python runtime. |
| `exp-platform/windows/dotnet` | Windows C# app, core library, and tests. |
| `exp-platform/python/toga` | Python Toga/BeeWare renderer experiment with headless runtime tests and benchmark markers. |
| `platform/typescript/exp/nodegui` | NodeGui/Qt TypeScript shell experiment. |

## AI docs layout

Platform-specific research and benchmark notes live under `docs/ai/platforms/`:

| Path | Focus |
| --- | --- |
| `docs/ai/platforms/apple-macos.md` | Apple/macOS app and performance testing notes. |
| `docs/ai/platforms/typescript-web.md` | TypeScript Web UI design research. |
| `docs/ai/platforms/windows.md` | Windows benchmark details. |
| `docs/ai/platforms/windows-native.md` | Native Windows implementation plan. |
| `docs/ai/platforms/go-gio.md` | Go Gio benchmark details. |
| `docs/ai/platforms/go-fyne.md` | Go Fyne renderer and benchmark notes. |
| `docs/ai/platforms/python-textual.md` | Python shared runtime, Textual, Tkinter, and wxPython renderer notes. |
| `docs/ai/platforms/dart-flutter.md` | Flutter benchmark details. |
| `docs/ai/platforms/rust-imgui.md` | Rust Dear ImGui benchmark details. |
| `docs/ai/platforms/rust-xilem-vello.md` | Rust Xilem/Vello headless core renderer status, commands, and UI blocker. |
| `docs/ai/platforms/python-toga.md` | Python Toga/BeeWare renderer notes, commands, and current gaps. |
| `docs/ai/platforms/rust-gpui.md` | Rust GPUI headless/core renderer notes and blocker. |

Cross-platform summaries, comparison reports, runtime-model research, and repository-wide architecture notes remain directly under `docs/ai/`.

## Stable commands

```bash
make setup-dev
make lint
make test
make build-cli
make project
make mac
make web
make tui
make test-webui
make test-toga
make build-release-all
```

## Experimental commands

```bash
make build-release-all-prototypes
make test-flutter
make test-compose
make test-android
make build-android
make run-compose-desktop
make build-compose-desktop
make test-gtk4
make build-gtk4
make test-slint
make test-raygui
make test-imgui
make test-iced
make build-iced
make test-makepad
make build-makepad-release
make test-egui
make test-xilem-vello
make build-xilem-vello
make benchmark-xilem-vello
make test-gpui
make build-gpui
make build-avalonia
make test-avalonia
make test-fyne
make run-toga
make benchmark-toga
make build-webui-dioxus
make build-gio-release
make test-qt-qml
make build-qt-qml
make build-fyne-release
make test-python
make test-textual
make run-textual
make run-tkinter
make run-wx
make benchmark-textual
make benchmark-tkinter
make benchmark-wx
```

On Windows, use `make.ps1` for the experimental Windows and cross-platform benchmark tasks:

```powershell
.\make.ps1 build
.\make.ps1 test-core
.\make.ps1 package-webui
.\make.ps1 package-electron
.\make.ps1 package-gio
```

## Build system notes

- Swift Package Manager remains the dependency source of truth for `GUIForCLICore` and `GUIForCLICLI`; the package root is `platform/apple`.
- Tuist (`platform/apple/Project.swift`) wires the SwiftUI Apple apps and experimental Apple targets into generated Xcode projects under `platform/apple`; it depends on `platform/apple/shared/Package.swift` so Xcode app generation does not resolve CLI-only packages.
- The TypeScript package root is `platform/typescript`; compiled output goes to the gitignored `platform/typescript/dist`.
- The Python Toga/BeeWare experiment uses `exp-platform/python/toga/src` as its import root. Top-level make targets set `PYTHONPATH` for headless tests, describe/once runs, and benchmark smoke checks without requiring the Toga UI dependency.
- The Kotlin Compose experiments live under `exp-platform/kotlin/compose`; Android and desktop entry points reuse the shared Kotlin runtime and Compose UI, while Android mounts `examples/` as assets so the WGS Extract bundle stays single-source.
- Web UI release packages stage the same `platform/typescript` and `resources/BuiltinStrings` paths used in development so runtime lookup stays consistent.
- The Avalonia experiment lives under `exp-platform/dotnet/avalonia`, references the reusable C# core in `exp-platform/windows/dotnet/GUIForCLIWindows.Core`, and uses top-level `make restore-avalonia`, `make build-avalonia`, `make run-avalonia`, `make test-avalonia`, and `make benchmark-avalonia` targets.
- Python renderer experiments share bundle loading, localization, interpolation, action state, process execution, data-source logic, and benchmark setup from `exp-platform/python/shared`; Textual, Tkinter, and wxPython are UI shells over that runtime.
- The top-level `Makefile` is for Unix-like development and release packaging; `make.ps1` owns Windows-specific tasks.
- Rust desktop experiments under `exp-platform/rust/*` reuse `exp-platform/rust/shared` for bundle loading, localization, workspace persistence, state/config writes, data-source/action conditions, process execution, terminal tabs, and benchmark summaries where possible.
- The GPUI experiment intentionally builds without the `gpui` crate until the Metal shader build failure is resolved; it still validates shared bundle/runtime behavior with `--check` and `--benchmark --once`.
- `make test-qt-qml` configures the Qt/QML source manifest without a Qt SDK; `make build-qt-qml`, `make run-qt-qml`, and `make benchmark-qt-qml` require Qt 6.5+ development packages.
