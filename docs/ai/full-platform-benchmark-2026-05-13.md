# Full platform benchmark run - 2026-05-13

Benchmarked on **2026-05-13 15:38 PDT** from `main` commit `759bdcb57f4c927e3b035602997ec1b38902c255`.

Host: **macOS 26.4.1 (25E253)**, **Apple M1 Pro**, **arm64**, **32 GB RAM**. Toolchain snapshot: Swift 6.3.1, Node 25.9.0, npm 11.12.1, Cargo 1.95.0, Go 1.26.3, Flutter 3.41.9, CMake 4.3.2, Gradle 9.5.1. `dotnet` was not installed.

Raw logs were captured locally in `out/benchmark-runs/20260513-153820` and are intentionally not committed.

## Scope

This pass ran every benchmark target exposed by `make help`:

- `make benchmark ARGS='startup-sequential'` (formerly `measure-startup-sequential`)
- `gio`
- `fyne`
- `flutter-windows`
- `flutter`
- `gtk4`
- `slint`
- `raygui`
- `raygui-c`
- `imgui`
- `iced`
- `makepad`
- `egui`
- `imgui-cpp`
- `qt-qml`
- `avalonia`

Compose Multiplatform Desktop, Jetpack Compose Android, NodeGui/Qt, iOS SwiftUI, AppKit, Objective-C AppKit, TypeScript TUI, and Windows C#/WinUI do not currently expose comparable benchmark targets in this checkout, so they are listed under gaps instead of being given synthetic numbers.

## Successful measurements

| Surface | Target | Size | Ready metric | Ready time | RSS | Samples | Notes |
| --- | --- | ---: | --- | ---: | ---: | ---: | --- |
| C++ Dear ImGui | `imgui-cpp` | 1.3 MB binary | internal `ui_ready_ms` | 4.5 ms | n/a | 1 | Fastest internal UI-ready marker. `full_feature_warm_ms=302.2`; loaded 4 data source rows. |
| Makepad | `makepad` | 8.1 MB binary | internal `ui_ready_ms` | 17.9 ms | n/a | 1 | `full_feature_warm_ms=560.5`; loaded 12 data source rows. |
| Rust egui | `egui` | 6.9 MB binary | internal `ui_ready_ms` | 19.8 ms | n/a | 1 | `full_feature_warm_ms=575.8`; loaded 12 data source rows. |
| Iced | `iced` | 9.3 MB binary | internal `ui_ready_ms` | 25.0 ms | n/a | 1 | `full_feature_warm_ms=508.3`; loaded 10 data source rows. |
| Rust Dear ImGui | `imgui` | 3.6 MB binary | internal `ui_ready_ms` | 28.1 ms | n/a | 1 | `full_feature_warm_ms=568.3`; loaded 12 data source rows. |
| Go Gio | `gio` | 8.4 MB release dir; 6.6 MB binary | internal `firstFrameRenderedMs` | 282.5 ms median | 187.3 MB median | 7 | Window configured at 9.1 ms median. |
| C Raygui | `raygui-c` | 1.1 MB binary | internal `ui_ready_ms` | 429.3 ms | n/a | 1 | Smallest measured binary. `full_feature_warm_ms=211.6`; loaded 5 data source rows. |
| Fyne | `fyne` | 25 MB release dir; 23 MB binary | internal `firstFrameRenderedMs` | 590.8 ms median | 355.2 MB median | 7 | Window configured at 239.7 ms median. |
| Slint | `slint` | 13 MB binary | internal `ui_ready_ms` | 662.7 ms | n/a | 1 | `full_feature_warm_ms=363.2`; loaded 12 data source rows. |
| Flutter macOS | `flutter` | 40.3 MB `.app` | external content-ready marker | 561.1 ms median | 127.2 MB median | 7 | Internal Dart marker median was 374.9 ms. First run was a cold outlier at 1711.6 ms external. |
| Tauri WebUI shell | Current equivalent: `make benchmark ARGS='startup-sequential'` | 118 MB `.app` | internal `webAppRendered_ms` | 660.5 ms | n/a | 1 | Sequential startup harness after `make setup-webui`; `windowShown_ms=453.8`, `webNavigationDidFinish_ms=557.6`. |

## Target status

| Target | Result | Runtime | Notes |
| --- | --- | ---: | --- |
| `make benchmark ARGS='startup-sequential'` | success on rerun | 84s | Initial attempt failed because TypeScript dependencies were not installed; `make setup-webui` fixed it. Only Tauri emitted benchmark metrics in its log. |
| `gio` | success | 11s | 7-sample JSON output. |
| `fyne` | success | 23s | 7-sample JSON output. |
| `flutter-windows` | skipped by target | 0s | Windows PowerShell benchmark target skipped because `pwsh` is not installed. |
| `flutter` | success | 32s | 7-sample marker run. |
| `gtk4` | failed | 7s | Missing local GTK stack: `gdk-pixbuf-2.0`, `gtk4`, and `graphene-gobject-1.0` were not discoverable by `pkg-config`. |
| `slint` | success | 53s | One-shot internal marker. |
| `raygui` | failed twice | 21s initial; 1s rerun | Rust Raygui built, then segfaulted after `GLFW: Failed to determine Monitor to center Window`. |
| `raygui-c` | success | 41s | One-shot internal marker. |
| `imgui` | success | 18s | One-shot internal marker. |
| `iced` | success | 33s | One-shot internal marker. |
| `makepad` | success | 21s | One-shot internal marker. |
| `egui` | success | 27s | One-shot internal marker. |
| `imgui-cpp` | success | 46s | One-shot internal marker. |
| `qt-qml` | failed | 1s | Qt 6.5+ development package was not installed or not on `CMAKE_PREFIX_PATH`. |
| `avalonia` | failed | 0s | `dotnet` was not installed. |

## Observations

1. The smallest successful native binaries were **C Raygui** at 1.1 MB and **C++ Dear ImGui** at 1.3 MB.
2. The fastest successful internal UI-ready marker was **C++ Dear ImGui** at 4.5 ms, followed by **Makepad**, **egui**, **Iced**, and **Rust Dear ImGui** in the 18-28 ms range.
3. Among multi-sample benchmarks with RSS capture, **Flutter** had the lowest median RSS at 127.2 MB, **Go Gio** was 187.3 MB, and **Fyne** was 355.2 MB.
4. **Tauri** produced a complete WebUI rendered metric in the sequential harness at 660.5 ms, but that pass did not capture RSS.
5. **GTK4**, **Qt/QML**, and **Avalonia** need local dependency setup before they can be compared on this machine. **Rust Raygui** needs a macOS window-positioning crash fix or benchmark-mode workaround.

## Gaps for future runs

- Add benchmark targets for Compose Multiplatform Desktop and Jetpack Compose Android.
- Add comparable benchmark targets for NodeGui/Qt, iOS SwiftUI, Swift AppKit, Objective-C AppKit, TypeScript TUI, and Windows C#/WinUI.
- Extend one-shot internal benchmarks to capture RSS and, where practical, app or package size automatically.
- Keep `make benchmark ARGS='startup-sequential'` dependency errors clear when TypeScript `node_modules` are missing.
