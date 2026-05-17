# GUI for CLI

> [!WARNING]
> This project is a work in progress. The bundle schema, setup flow, and app UI are still changing and should not be treated as stable.

GUI for CLI turns small CLI-tool bundles into graphical and terminal front ends. The stable surfaces are the native SwiftUI macOS app, the TypeScript Web UI and its packaged shells, and the TypeScript terminal UI. Other renderers and platform prototypes live under `platform/*/exp/` or `exp-platform/`.

![GUI for CLI macOS app showing the WGS Extract example bundle](docs/readme-screenshot.png)

## Stable surfaces

| Surface | Path | Command |
| --- | --- | --- |
| SwiftUI macOS app | `platform/apple/swiftui` plus `platform/apple/shared` | `make run PLATFORM=swiftui-macos` |
| Web UI | `platform/typescript/web` plus `platform/typescript/shared` | `make run PLATFORM=webui` |
| TypeScript TUI | `platform/typescript/tui` plus `platform/typescript/shared` | `make run PLATFORM=tui` |
| Web UI packagers | `platform/typescript/web/packagers/*` | `make package PLATFORM=webview`, `make package PLATFORM=tauri`, `make package PLATFORM=electron` |

## Platform split

Stable code is grouped by platform under `platform/`; experimental platform-specific work lives in the owning platform's `exp/` folder, while cross-platform prototype renderers live under `exp-platform/`.

| Status | Count | Surfaces |
| --- | ---: | --- |
| Stable platform groups | 2 | Apple, TypeScript |
| Stable surfaces | 4 | SwiftUI macOS app, TypeScript Web UI, TypeScript TUI, Web UI packagers |
| Experimental platform groups | 12 | Apple, TypeScript, Rust, Dart, C, C++, Go, Python, Mojo, .NET, Kotlin, Windows |
| Experimental surfaces | 29 | iOS SwiftUI app, Swift AppKit, Objective-C AppKit, NodeGui/Qt, Dioxus shell, GTK4/libadwaita, Slint, Rust ImGui, Iced, Rust egui, Rust Xilem/Vello, Rust GPUI headless/core, Raygui, Makepad, Flutter, C Raygui, C++ ImGui, Qt 6/QML, Go Gio, Go Fyne, Python Textual, Python Tkinter, Python wxPython, Python Toga/BeeWare, Mojo headless/core, Avalonia, Compose Multiplatform Desktop, Jetpack Compose Android, Windows C#/WinUI |

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
| Experimental | Rust Xilem/Vello | `exp-platform/rust/xilem-vello` | Headless shared-core renderer while the Xilem/Vello window API stabilizes. |
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
| Experimental | Python shared runtime | `exp-platform/python/shared` | Shared Python bundle/runtime helpers for Python renderer experiments. |
| Experimental | Python Textual | `exp-platform/python/textual` | Python terminal UI renderer experiment with headless core tests and benchmark mode. |
| Experimental | Python Tkinter | `exp-platform/python/tkinter` | Stdlib desktop GUI renderer experiment using the shared Python runtime. |
| Experimental | Python wxPython | `exp-platform/python/wx` | wxPython desktop GUI renderer experiment using the shared Python runtime; UI dependency is optional for headless smoke tests. |
| Experimental | Mojo headless/core | `exp-platform/mojo` | Mojo renderer experiment with Pixi-managed tooling and Python-renderer-style headless bundle/runtime validation. |
| Experimental | Compose Multiplatform Desktop | `exp-platform/kotlin/compose/desktopApp` plus `exp-platform/kotlin/compose/shared` | Kotlin Compose desktop renderer experiment. |
| Experimental | Jetpack Compose Android | `exp-platform/kotlin/compose/androidApp` plus `exp-platform/kotlin/compose/shared` | Android Compose renderer experiment. |
| Experimental | Windows C#/WinUI | `exp-platform/windows/dotnet` | Windows platform experiment. |
| Experimental | Python Toga/BeeWare | `exp-platform/python/toga` | Python desktop renderer experiment with headless bundle/runtime validation and benchmark markers. |

See `docs/ai/development-architecture.md` for the full repository layout and command map.

## Requirements

- Xcode 16 or newer with Swift 6 and `swift format`.
- [Tuist](https://tuist.dev) for app workspace generation.
- Node.js 18 or newer for the TypeScript Web UI/TUI development workflow.
- Rust/Cargo only when building Tauri or experimental Rust prototypes. The GTK4/libadwaita prototype also needs system GTK4 and libadwaita development packages discoverable by `pkg-config`.
- .NET SDK 10 or newer only when building the experimental WinUI or Avalonia prototypes.
- CMake and a C/C++ toolchain only when building the experimental C Raygui, C++ ImGui, or Qt 6/QML prototypes. Qt 6.5 or newer is required for `make build PLATFORM=qt-qml`.
- Go 1.25 or newer when building experimental Go Gio/Fyne prototypes.
- Python 3.11 or newer for dev tooling and experimental Python renderers. Use [uv](https://docs.astral.sh/uv/) from the repo root (`uv run python ...`) so the root `pyproject.toml` / `.python-version` policy is honored. Tkinter needs a Python build with `tkinter`; wxPython is optional and installed by `make setup PLATFORM=wx`; install the Toga/BeeWare package before launching its UI.
- Pixi when running the experimental Mojo renderer; `make setup PLATFORM=mojo`, `make test PLATFORM=mojo`, and `make run PLATFORM=mojo` install/use the pinned Mojo toolchain from `exp-platform/mojo/pixi.lock`.
- JDK 17 or newer when building experimental Kotlin Compose prototypes.
- Optional: [mise](https://mise.jdx.dev) can install the pinned Tuist version from `.mise.toml`.

## Getting started

```bash
make setup
swift run --package-path platform/apple gui-for-cli precheck
swift run --package-path platform/apple gui-for-cli config init
make setup PLATFORM=apple-project
open platform/apple/GUIForCLI.xcworkspace
```

Run the stable surfaces, plus the Python experiment when desired:

```bash
make run PLATFORM=swiftui-macos
make run PLATFORM=webui BUNDLE=examples/WGSExtract
make run PLATFORM=tui BUNDLE=examples/WGSExtract
make run PLATFORM=toga BUNDLE=examples/WGSExtract
```

The CLI remains available directly:

```bash
swift run --package-path platform/apple gui-for-cli run --name Swift
```

## Common commands

| Command | Purpose |
| --- | --- |
| `make lint` | Run the stable lint suite through the platform runner. |
| `make platforms` | List platform names with their runner capabilities. |
| `make test PLATFORM=swift` | Run Swift package tests. |
| `make build PLATFORM=cli` | Build the release CLI. |
| `make test PLATFORM=webui` | Build and run TypeScript Web UI/TUI tests. |
| `make test PLATFORM=toga` / `make run PLATFORM=toga` / `make benchmark ARGS='toga'` | Test, run, or benchmark the experimental Python Toga/BeeWare renderer. |
| `make build PLATFORM=dioxus` / `make run PLATFORM=dioxus` | Build or run the experimental Dioxus native Web UI shell. |
| `make test PLATFORM=flutter` / `make run PLATFORM=flutter` / `make build PLATFORM=flutter` | Test, run, or build the experimental Flutter macOS renderer. |
| `make test PLATFORM=gtk4` | Run static checks for the GTK4 renderer core without requiring system GTK libraries. |
| `make run PLATFORM=gtk4` | Build and run the experimental GTK4/libadwaita renderer. |
| `make build PLATFORM=slint` / `make run PLATFORM=slint` | Build or run the experimental Rust Slint renderer. |
| `make test PLATFORM=raygui` / `make build PLATFORM=raygui` / `make run PLATFORM=raygui` | Test, build, or run the experimental Rust Raygui renderer. |
| `make test PLATFORM=imgui` / `make build PLATFORM=imgui` / `make run PLATFORM=imgui` | Test, build, or run the experimental Rust Dear ImGui renderer. |
| `make test PLATFORM=iced` / `make build PLATFORM=iced` / `make run PLATFORM=iced` | Test, build, or run the experimental Rust Iced renderer. |
| `make test PLATFORM=makepad` / `make build PLATFORM=makepad` / `make run PLATFORM=makepad` | Test, build, or run the experimental Rust Makepad renderer. |
| `make test PLATFORM=egui` / `make build PLATFORM=egui` / `make run PLATFORM=egui` | Test, build, or run the experimental Rust egui renderer. |
| `make test PLATFORM=xilem-vello` / `make build PLATFORM=xilem-vello` / `make run PLATFORM=xilem-vello` / `make benchmark ARGS='xilem-vello'` | Test, build, run, or benchmark the experimental Rust Xilem/Vello renderer. |
| `make test PLATFORM=gpui` / `make build PLATFORM=gpui` / `make run PLATFORM=gpui` / `make benchmark ARGS='gpui'` | Test, build, run, or benchmark the experimental Rust GPUI renderer. |
| `make build PLATFORM=raygui-c` / `make run PLATFORM=raygui-c` | Build or run the experimental C Raygui renderer. |
| `make build PLATFORM=imgui-cpp` / `make run PLATFORM=imgui-cpp` | Build or run the experimental C++ Dear ImGui renderer. |
| `make build PLATFORM=avalonia` / `make run PLATFORM=avalonia` / `make test PLATFORM=avalonia` | Build, run, and validate the experimental Avalonia renderer. |
| `make package PLATFORM=gio` | Build and stage the experimental Go Gio renderer. |
| `make test PLATFORM=fyne` / `make build PLATFORM=fyne` / `make run PLATFORM=fyne` | Test, build, or run the experimental Go Fyne renderer. |
| `make test PLATFORM=python` / `make run PLATFORM=tkinter` / `make run PLATFORM=wx` | Test or run the experimental shared Python runtime and desktop renderers. |
| `make test PLATFORM=textual` / `make run PLATFORM=textual` / `make benchmark ARGS='textual'` | Test, run, or benchmark the experimental Python Textual renderer. |
| `make test PLATFORM=compose` / `make build PLATFORM=compose-desktop` / `make run PLATFORM=compose-desktop` | Test, build, or run the experimental Compose Multiplatform desktop renderer. |
| `make test PLATFORM=android` / `make build PLATFORM=android` | Test or build the experimental Jetpack Compose Android renderer. |
| `make package PLATFORM=swift` | Build a macOS SwiftUI distribution folder with `.app` and `.dmg` output; signs/notarizes when Apple credentials are configured. |
| `make package PLATFORM=tauri` | Build Tauri desktop distribution artifacts for the current OS: macOS `.app` + `.dmg`, Linux `.deb` + `.AppImage`, or Windows NSIS installer. |
| `make package PLATFORM=webui` | Stage a standalone Web UI release folder with bundled Node. |
| `make release-build SUITE=stable` | Build stable release options. |
| `make test PLATFORM=qt-qml` / `make build PLATFORM=qt-qml` | Validate or build the experimental Qt 6/QML renderer. |
| `make release-build SUITE=all` | Build stable releases plus experimental prototypes. |
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

## Distribution packaging

See [`docs/distribution.md`](docs/distribution.md) for the full signing, notarization, and CI artifact flow.

Preferred local signing setup flow:

```bash
uv run python scripts/dev.py signing autosetup
```

If autosetup reports expired identities, remove them with:

```bash
uv run python scripts/dev.py signing delete-expired-identities
```

Use `--dry-run` to preview the cleanup.

Quick start:

```bash
make setup PLATFORM=apple-project
make package PLATFORM=swift
make package PLATFORM=tauri
```

Bundle-branded packaging is also supported. Set `packaging.embedded_bundle_path` and `packaging.app_name` in `.devconfig.toml`, then package normally.

Signed SwiftUI releases require a Developer ID Application identity in the keychain locally, or `APPLE_CERTIFICATE_P12` / `APPLE_CERTIFICATE_PASSWORD` secrets in CI.

`out/release/swiftui/` now contains the SwiftUI macOS `.app` and `.dmg`, while `out/release/tauri/` contains the current-platform Tauri distributables.

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
