# Desktop GUI experiments

GUI for CLI has two product frontends:

| Frontend | Role | Current command |
| --- | --- | --- |
| `swiftui-macos` | Native macOS desktop app and primary Apple direction. | `make run PLATFORM=swiftui-macos` |
| `tauri-webui` | Portable packaged WebUI desktop app. | `make run PLATFORM=tauri` |

Everything else in this document is research, benchmark infrastructure, or a prototype renderer. The experiments are useful because they exposed runtime tradeoffs and forced the bundle model to stay portable, but they are not supported frontends.

## What the experiments tested

The research pass tried multiple UI stacks against the same bundle shape instead of comparing empty windows. The WGSExtract bundle made the tests realistic because it includes setup, command rendering, file pickers, dynamic rows, localization, terminal output, long-running process state, and distribution packaging.

| Question | Result |
| --- | --- |
| Is a native macOS frontend worth keeping? | Yes. SwiftUI remains the best integrated macOS app path and the lowest-memory production frontend. |
| Is a WebUI desktop shell still useful? | Yes. Tauri gives a self-contained app model around the reusable TypeScript WebUI and is the portable WebUI frontend. |
| Should Electron be the default desktop shell? | No. Startup can be competitive, but package size and memory are much higher than Tauri/WebView paths. |
| Should browser launch be the product UX? | No. An already-open browser is useful for preview and development, but cold browser memory dominates the experience. |
| Did smaller native prototypes beat the product frontends on narrow metrics? | Often. Slint, Raygui, ImGui, Gio, Flutter, and others produced useful benchmark signals, but none replaced the complete SwiftUI/Tauri product split. |

## Current platform split

Stable product code is grouped under `platform/`. Experimental platform-specific work lives in the owning platform's `exp/` folder, while cross-platform prototype renderers live under `exp-platform/`.

| Status | Count | Surfaces |
| --- | ---: | --- |
| Product frontends | 2 | `swiftui-macos`, `tauri-webui` |
| Product support surfaces | 3 | Swift CLI, TypeScript Web UI server/client, TypeScript shared runtime |
| Experimental platform groups | 12 | Apple, TypeScript, Rust, Dart, C, C++, Go, Python, Mojo, .NET, Kotlin, Windows |
| Experimental surfaces | 29 | iOS SwiftUI app, Swift AppKit, Objective-C AppKit, NodeGui/Qt, Dioxus shell, GTK4/libadwaita, Slint, Rust ImGui, Iced, Rust egui, Rust Xilem/Vello, Rust GPUI headless/core, Raygui, Makepad, Flutter, C Raygui, C++ ImGui, Qt 6/QML, Go Gio, Go Fyne, Python Textual, Python Tkinter, Python wxPython, Python Toga/BeeWare, Mojo headless/core, Avalonia, Compose Multiplatform Desktop, Jetpack Compose Android, Windows C#/WinUI |

## Experiment inventory

| Status | Surface | Path | Notes |
| --- | --- | --- | --- |
| Product | `swiftui-macos` | `platform/apple/swiftui` plus `platform/apple/shared` | Native macOS SwiftUI target. |
| Product | `tauri-webui` | `platform/typescript/web` plus `platform/typescript/web/packagers/tauri` | Packaged desktop shell for the reusable WebUI. |
| Support | Swift CLI | `platform/apple/shared/Sources/GUIForCLICLI` | Bundle inspection, setup, and terminal command surface. |
| Support | TypeScript Web UI server/client | `platform/typescript/web` | Browser/server implementation reused by Tauri. |
| Experimental | iOS SwiftUI app | `platform/apple/exp/ios-swiftui` plus `platform/apple/shared` | Native iOS SwiftUI target, not Mac Catalyst. |
| Experimental | Swift AppKit | `platform/apple/exp/swift-appkit` | Apple platform experiment. |
| Experimental | Objective-C AppKit | `platform/apple/exp/objc-appkit` | Apple platform experiment. |
| Experimental | NodeGui/Qt | `platform/typescript/exp/nodegui` | TypeScript platform experiment. |
| Experimental | Dioxus shell | `exp-platform/rust/dioxus-shell` | Rust platform experiment. |
| Experimental | GTK4/libadwaita | `exp-platform/rust/gtk4` | Native GTK4/libadwaita Rust renderer experiment. |
| Experimental | Slint | `exp-platform/rust/slint` | Rust renderer experiment with strong footprint/startup signals. |
| Experimental | Rust ImGui | `exp-platform/rust/imgui` | Rust immediate-mode GUI experiment. |
| Experimental | Iced | `exp-platform/rust/iced` | Rust desktop renderer experiment. |
| Experimental | Rust egui | `exp-platform/rust/egui` | Rust eframe/egui desktop renderer experiment. |
| Experimental | Rust Xilem/Vello | `exp-platform/rust/xilem-vello` | Headless/shared-core renderer while Xilem/Vello window APIs stabilize. |
| Experimental | Rust GPUI headless/core | `exp-platform/rust/gpui` | Shared-core runner with GPUI research history. |
| Experimental | Raygui | `exp-platform/rust/raygui` | Small native-rendered Rust prototype. |
| Experimental | Makepad | `exp-platform/rust/makepad` | Rust Makepad desktop renderer experiment. |
| Experimental | Flutter | `exp-platform/dart/flutter` | Dart platform experiment and cross-platform native-rendered comparison. |
| Experimental | C Raygui | `exp-platform/c/raygui` | C Raygui desktop GUI experiment. |
| Experimental | C++ ImGui | `exp-platform/cpp/imgui-cpp` | C++ immediate-mode GUI experiment. |
| Experimental | Qt 6/QML | `exp-platform/cpp/qt-qml` | C++/Qt Quick Controls experiment with QML app shell, terminal tabs, data sources, and benchmark markers. |
| Experimental | Go Gio | `exp-platform/go/gio` | Go native GUI experiment. |
| Experimental | Avalonia | `exp-platform/dotnet/avalonia` | Cross-platform .NET desktop experiment. |
| Experimental | Go Fyne | `exp-platform/go/fyne` | Go Fyne desktop renderer experiment. |
| Experimental | Python shared runtime | `exp-platform/python/shared` | Shared Python bundle/runtime helpers for Python renderer experiments. |
| Experimental | Python Textual | `exp-platform/python/textual` | Python terminal UI renderer experiment with headless core tests and benchmark mode. |
| Experimental | Python Tkinter | `exp-platform/python/tkinter` | Stdlib desktop GUI renderer experiment using the shared Python runtime. |
| Experimental | Python wxPython | `exp-platform/python/wx` | wxPython desktop GUI renderer experiment using the shared Python runtime. |
| Experimental | Mojo headless/core | `exp-platform/mojo` | Mojo renderer experiment with Pixi-managed tooling and Python-renderer-style validation. |
| Experimental | Compose Multiplatform Desktop | `exp-platform/kotlin/compose/desktopApp` plus `exp-platform/kotlin/compose/shared` | Kotlin Compose desktop renderer experiment. |
| Experimental | Jetpack Compose Android | `exp-platform/kotlin/compose/androidApp` plus `exp-platform/kotlin/compose/shared` | Android Compose renderer experiment. |
| Experimental | Windows C#/WinUI | `exp-platform/windows/dotnet` | Windows platform experiment. |
| Experimental | Python Toga/BeeWare | `exp-platform/python/toga` | Python desktop renderer experiment with headless runtime validation and benchmark markers. |

## Benchmark results that shaped the decision

The benchmark docs under `docs/ai/` contain raw methods and run notes. The short version:

| Surface | Result | Decision impact |
| --- | --- | --- |
| SwiftUI macOS | Native app package around 9 MB in benchmark reports; measured macOS window readiness around 196-216 ms in marker runs, with later visual captures showing where startup work still needed tuning. | Keep as the primary macOS product frontend because it is native, integrated, small, and complete. |
| Tauri WebUI | Self-contained WebUI app around 118 MB on macOS in benchmark reports; portable app model with less custom shell code than bespoke WebView shells. | Keep as the portable WebUI product frontend. |
| WebView shell | Slightly leaner macOS WebUI shell in some runs, but macOS-only and custom. | Keep as benchmark/control tooling, not as a product frontend. |
| Electron | Runtime can be reasonable, but package and memory cost are much higher than Tauri/WebView paths. | Keep as a packaging benchmark/fallback only. |
| Browser WebUI | Fast when a browser is already open; cold browser launch has poor memory characteristics. | Keep for development/preview, not as the installed app frontend. |
| Slint/Raygui/ImGui/Gio/Flutter | Several prototypes won narrow startup, size, or memory categories. | Preserve the research, but do not promote any to a supported frontend until it reaches product parity. |
| TypeScript TUI/Textual terminal paths | Useful low-overhead terminal workflows. | Keep as developer/automation surfaces rather than desktop GUI frontends. |

## WGSExtract as the first real app

WGSExtract is the first bundle that made GUI for CLI behave like a product rather than a renderer demo. It forced the system to handle:

- multi-step setup scripts and external tool installation;
- long-running commands with terminal output and cancel state;
- file and directory pickers for real user data;
- localized strings and bundle-provided icon mappings;
- dynamic data-source rows and state-dependent actions;
- persisted configuration and bundle workspace state;
- bundle-specific release branding and packaging.

That pressure is why generic behavior belongs in `GUIForCLICore`, frontend-specific presentation belongs in `swiftui-macos` or `tauri-webui`, and prototypes stay isolated until they prove they can cover the same WGSExtract workflow.

See `docs/ai/development-architecture.md` for the full repository layout and command map, and `docs/ai/benchmark-findings.md` for the latest decision-oriented benchmark summary.
