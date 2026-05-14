# GUI for CLI

> [!WARNING]
> This project is a work in progress. The bundle schema, setup flow, and app UI are still changing and should not be treated as stable.

GUI for CLI turns small CLI-tool bundles into graphical and terminal front ends. The stable surfaces are the native SwiftUI macOS app, the TypeScript Web UI and its packaged shells, and the TypeScript terminal UI. Other renderers and platform prototypes live under `platform/*/exp/` or `exp-platform/`.

![GUI for CLI macOS app showing the WGS Extract example bundle](docs/readme-screenshot.png)

## Stable surfaces

| Surface | Path | Command |
| --- | --- | --- |
| SwiftUI macOS app | `platform/apple/swiftui` plus `platform/apple/shared` | `make mac` |
| Web UI | `platform/typescript/web` plus `platform/typescript/shared` | `make web` |
| TypeScript TUI | `platform/typescript/tui` plus `platform/typescript/shared` | `make tui` |
| Web UI packagers | `platform/typescript/web/packagers/*` | `make build-webview-release`, `make build-tauri-release`, `make build-electron-release` |

## Platform split

Stable code is grouped by platform under `platform/`; experimental platform-specific work lives in the owning platform's `exp/` folder, while cross-platform prototype renderers live under `exp-platform/`.

| Status | Count | Surfaces |
| --- | ---: | --- |
| Stable platform groups | 2 | Apple, TypeScript |
| Stable surfaces | 4 | SwiftUI macOS app, TypeScript Web UI, TypeScript TUI, Web UI packagers |
| Experimental platform groups | 10 | Apple, TypeScript, Rust, Dart, C, C++, Go, .NET, Kotlin, Windows |
| Experimental surfaces | 23 | iOS SwiftUI app, Swift AppKit, Objective-C AppKit, NodeGui/Qt, Dioxus shell, GTK4/libadwaita, Slint, Rust ImGui, Iced, Rust egui, Rust GPUI headless/core, Raygui, Makepad, Flutter, C Raygui, C++ ImGui, Qt 6/QML, Go Gio, Go Fyne, Avalonia, Compose Multiplatform Desktop, Jetpack Compose Android, Windows C#/WinUI |

| Status | Surface | Path | Notes |
| --- | --- | --- | --- |
| Stable | SwiftUI macOS app | `platform/apple/swiftui` plus `platform/apple/shared` | Native macOS SwiftUI target. |
| Stable | Web UI | `platform/typescript/web` plus `platform/typescript/shared` | Browser UI and local Node backend. |
| Stable | TypeScript TUI | `platform/typescript/tui` plus `platform/typescript/shared` | Terminal-first UI. |
| Stable | Web UI packagers | `platform/typescript/web/packagers/*` | WKWebView shell, Tauri, and Electron. |
| Experimental | iOS SwiftUI app | `platform/apple/exp/ios-swiftui` plus `platform/apple/shared` | Native iOS SwiftUI target, not Mac Catalyst. |
| Experimental | Swift AppKit | `platform/apple/exp/swift-appkit` | Apple platform experiment. |
| Experimental | Objective-C AppKit | `platform/apple/exp/objc-appkit` | Apple platform experiment. |
| Experimental | NodeGui/Qt | `platform/typescript/exp/nodegui` | TypeScript platform experiment. |
| Experimental | Dioxus shell | `exp-platform/rust/dioxus-shell` | Rust platform experiment. |
| Experimental | GTK4/libadwaita | `exp-platform/rust/gtk4` | Native GTK4/libadwaita Rust renderer experiment. Requires GTK4/libadwaita development libraries for UI builds. |
| Experimental | Slint | `exp-platform/rust/slint` | Rust platform experiment. |
| Experimental | Rust ImGui | `exp-platform/rust/imgui` | Rust platform experiment. |
| Experimental | Iced | `exp-platform/rust/iced` | Rust platform experiment with a native desktop app shell. |
| Experimental | Rust egui | `exp-platform/rust/egui` | Rust eframe/egui desktop renderer experiment. |
| Experimental | Rust GPUI headless/core | `exp-platform/rust/gpui` | Rust GPUI renderer experiment currently limited to a compiled headless/core runner because the published GPUI crate fails its Metal shader build in this worktree. |
| Experimental | Raygui | `exp-platform/rust/raygui` | Rust platform experiment. |
| Experimental | Makepad | `exp-platform/rust/makepad` | Rust Makepad desktop renderer experiment. |
| Experimental | Flutter | `exp-platform/dart/flutter` | Dart platform experiment. |
| Experimental | C Raygui | `exp-platform/c/raygui` | C Raygui desktop renderer experiment. |
| Experimental | C++ ImGui | `exp-platform/cpp/imgui-cpp` | C++ platform experiment. |
| Experimental | Qt 6/QML | `exp-platform/cpp/qt-qml` | C++/Qt Quick Controls experiment with QML app shell, terminal tabs, data sources, and benchmark markers. |
| Experimental | Go Gio | `exp-platform/go/gio` | Go platform experiment. |
| Experimental | Avalonia | `exp-platform/dotnet/avalonia` | Cross-platform .NET desktop experiment. |
| Experimental | Go Fyne | `exp-platform/go/fyne` | Go Fyne desktop renderer experiment. |
| Experimental | Compose Multiplatform Desktop | `exp-platform/kotlin/compose/desktopApp` plus `exp-platform/kotlin/compose/shared` | Kotlin Compose desktop renderer experiment. |
| Experimental | Jetpack Compose Android | `exp-platform/kotlin/compose/androidApp` plus `exp-platform/kotlin/compose/shared` | Android Compose renderer experiment. |
| Experimental | Windows C#/WinUI | `exp-platform/windows/dotnet` | Windows platform experiment. |

See `docs/ai/development-architecture.md` for the full repository layout and command map.

## Requirements

- Xcode 16 or newer with Swift 6 and `swift format`.
- [Tuist](https://tuist.dev) for app workspace generation.
- Node.js 18 or newer for the TypeScript Web UI/TUI development workflow.
- Rust/Cargo only when building Tauri or experimental Rust prototypes. The GTK4/libadwaita prototype also needs system GTK4 and libadwaita development packages discoverable by `pkg-config`.
- .NET SDK 10 or newer only when building the experimental WinUI or Avalonia prototypes.
- CMake and a C/C++ toolchain only when building the experimental C Raygui, C++ ImGui, or Qt 6/QML prototypes. Qt 6.5 or newer is required for `make build-qt-qml`.
- Go 1.25 or newer when building experimental Go Gio/Fyne prototypes.
- JDK 17 or newer when building experimental Kotlin Compose prototypes.
- Optional: [mise](https://mise.jdx.dev) can install the pinned Tuist version from `.mise.toml`.

## Getting started

```bash
swift package --package-path platform/apple resolve
make setup-webui
swift run --package-path platform/apple gui-for-cli precheck
swift run --package-path platform/apple gui-for-cli config init
make project
open platform/apple/GUIForCLI.xcworkspace
```

Run the stable surfaces:

```bash
make mac
make web BUNDLE=examples/WGSExtract
make tui BUNDLE=examples/WGSExtract
```

The CLI remains available directly:

```bash
swift run --package-path platform/apple gui-for-cli run --name Swift
```

## Common commands

| Command | Purpose |
| --- | --- |
| `make lint` | Run Swift formatting lint. |
| `make test` | Run Swift package tests. |
| `make build-cli` | Build the release CLI. |
| `make test-webui` | Build and run TypeScript Web UI/TUI tests. |
| `make build-webui-dioxus` / `make run-webui-dioxus` | Build or run the experimental Dioxus native Web UI shell. |
| `make test-flutter` / `make flutter` / `make flutter-build` | Test, run, or build the experimental Flutter macOS renderer. |
| `make test-gtk4` | Run static checks for the GTK4 renderer core without requiring system GTK libraries. |
| `make run-gtk4` | Build and run the experimental GTK4/libadwaita renderer. |
| `make build-slint` / `make run-slint` | Build or run the experimental Rust Slint renderer. |
| `make test-raygui` / `make build-raygui` / `make run-raygui` | Test, build, or run the experimental Rust Raygui renderer. |
| `make test-imgui` / `make build-imgui` / `make run-imgui` | Test, build, or run the experimental Rust Dear ImGui renderer. |
| `make test-iced` / `make build-iced` / `make run-iced` | Test, build, or run the experimental Rust Iced renderer. |
| `make test-makepad` / `make build-makepad` / `make run-makepad` | Test, build, or run the experimental Rust Makepad renderer. |
| `make test-egui` / `make build-egui` / `make run-egui` | Test, build, or run the experimental Rust egui renderer. |
| `make test-gpui` / `make build-gpui` / `make run-gpui` / `make benchmark-gpui` | Test, build, run, or benchmark the experimental Rust GPUI headless/core renderer. |
| `make build-raygui-c` / `make run-raygui-c` | Build or run the experimental C Raygui renderer. |
| `make build-imgui-cpp` / `make run-imgui-cpp` | Build or run the experimental C++ Dear ImGui renderer. |
| `make build-avalonia` / `make run-avalonia` / `make test-avalonia` | Build, run, and validate the experimental Avalonia renderer. |
| `make build-gio-release` | Build and stage the experimental Go Gio renderer. |
| `make test-fyne` / `make build-fyne` / `make run-fyne` | Test, build, or run the experimental Go Fyne renderer. |
| `make test-compose` / `make build-compose-desktop` / `make run-compose-desktop` | Test, build, or run the experimental Compose Multiplatform desktop renderer. |
| `make test-android` / `make build-android` | Test or build the experimental Jetpack Compose Android renderer. |
| `make build-swift-release` | Stage the SwiftUI macOS release app. |
| `make build-webui-release` | Stage a standalone Web UI release folder with bundled Node. |
| `make build-release-all` | Build stable release options. |
| `make test-qt-qml` / `make build-qt-qml` | Validate or build the experimental Qt 6/QML renderer. |
| `make build-release-all-prototypes` | Build stable releases plus experimental prototypes. |
| `make ci` / `make ci-fast` | Run local CI checks. |

## Bundles

A bundle is a folder or supported archive containing `manifest.json`. The loader accepts a bundle folder, a folder/archive with one top-level child containing `manifest.json`, a direct `manifest.json` file, and `.zip`, `.tar`, `.tar.gz`, `.tgz`, or single-manifest `.gz` archives on macOS.

```bash
swift run --package-path platform/apple gui-for-cli bundle inspect examples/WGSExtract
swift run --package-path platform/apple gui-for-cli bundle setup --dry-run examples/WGSExtract
swift run --package-path platform/apple gui-for-cli bundle write-demo tmp/WGSExtract.gui-cli --force
```

Bundles can include `strings.toml` and `strings.<language-code>.toml` localization tables next to `manifest.json`. Schema files live in `docs/schema/manifest.schema.json` and `docs/schema/page.schema.json`.

## Configuration

Configuration is stored in the platform Application Support directory:

```text
$HOME/Library/Application Support/gui-for-cli/config.json
```

Set `GUI_FOR_CLI_CONFIG_DIR` to override the config directory for isolated tests or scripts.

```bash
swift run --package-path platform/apple gui-for-cli config show
swift run --package-path platform/apple gui-for-cli config init --force
```

## Integrated app builds

The default app keeps the general `GUI for CLI` identity. For a bundle-specific local build, write an ignored identity file before regenerating the project:

```bash
mkdir -p tmp
printf '{ "embeddedBundlePath": "examples/WGSExtract" }\n' > tmp/app-identity.json
cd platform/apple
../../scripts/tuist.sh clean manifests
../../scripts/tuist.sh generate --no-open
```

`embeddedBundlePath` reads the bundle `manifest.json` and uses its `displayName` for the generated app display name and product name. Delete `tmp/app-identity.json` and regenerate after `cd platform/apple && ../../scripts/tuist.sh clean manifests` to return to the generic app identity.
