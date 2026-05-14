# Full platform benchmark run - 2026-05-14

Benchmarked on **2026-05-14 10:31-11:06 PDT** from local commit `5b558e7e6a4b26b4052b1c620e51dc3a0381dc83`.

Host: **macOS 26.4.1 (25E253)**, **Apple M1 Pro**, **arm64**, **32 GB RAM**. Toolchain snapshot: Swift 6.3.1, Xcode 26.4.1, Node 25.9.0, npm 11.12.1, Cargo 1.95.0, Go 1.26.3, Flutter 3.41.9, CMake 4.3.2, Gradle 9.5.1, .NET 10.0.107, GTK 4.22.4, Qt 6.11.0.

Raw logs were captured locally in `out/benchmark-runs/20260514-103128`, rerun folders `out/benchmark-runs/20260514-103128-rerun*`, and focused mobile rerun folder `out/benchmark-runs/20260514-124032-mobile-rerun`; they are intentionally not committed.

Mobile simulator/emulator boot and app installation time are setup phases, not startup metrics. The iOS and Android harnesses wait for the simulator/emulator to be ready before collecting samples, and their JSON output records setup time separately under `setup`.

## Scope

This pass covered every platform surface available from this macOS checkout:

- Stable Apple and TypeScript surfaces: SwiftUI macOS, Web UI packagers, and TypeScript TUI.
- Experimental Apple, TypeScript, Rust, C, C++, Go, Python, .NET, Dart, and Kotlin surfaces.
- Mobile simulator/emulator surfaces available on macOS: iOS Simulator and Android Emulator.

Windows C#/WinUI and the PowerShell-only Windows Flutter benchmark were excluded because they are not runnable on macOS.

## Successful measurements

| Surface | Target | Artifact size | Ready metric | Ready time | RSS | Samples | Notes |
| --- | --- | ---: | --- | ---: | ---: | ---: | --- |
| Python wxPython headless | `benchmark-wx` | n/a | `uiReady` | 4.9 ms | n/a | 1 | Headless shared-runtime render, no wx UI dependency required. |
| Python Tkinter headless | `benchmark-tkinter` | n/a | `uiReady` | 5.0 ms | n/a | 1 | Headless bundle load/render path without opening a window. |
| Python Textual headless | `benchmark-textual` | n/a | `uiReady` | 8.3 ms | n/a | 1 | Terminal/core render benchmark. |
| C++ Dear ImGui | `benchmark-imgui-cpp` | 1.3 MB binary | internal `ui_ready_ms` | 4.3 ms | n/a | 1 | `full_feature_warm_ms=295.1`; 4 data-source rows loaded. |
| Xilem/Vello headless | `benchmark-xilem-vello` | 1.6 MB binary | internal `ui_ready_ms` | 15.0 ms | n/a | 1 | Core/headless renderer; `full_feature_warm_ms=546.3`. |
| GPUI headless | `benchmark-gpui` | 1.6 MB binary | internal `ui_ready_ms` | 15.4 ms | n/a | 1 | Core/headless renderer; data-source execution currently disabled in this path. |
| Iced | `benchmark-iced` | 9.3 MB binary | internal `ui_ready_ms` | 16.5 ms | n/a | 1 | `full_feature_warm_ms=566.3`; 10 data-source rows loaded. |
| Makepad | `benchmark-makepad` | 8.1 MB binary | internal `ui_ready_ms` | 18.8 ms | n/a | 1 | `full_feature_warm_ms=595.1`. |
| Rust Dear ImGui | `benchmark-imgui` | 3.6 MB binary | internal `ui_ready_ms` | 19.1 ms | n/a | 1 | `full_feature_warm_ms=736.8`. |
| GTK4/libadwaita | `benchmark-gtk4` | 1.9 MB binary | internal `ui_ready_ms` | 19.5 ms | n/a | 1 | GTK stack is installed on this host; build issues found by the first pass were fixed. |
| Rust egui | `benchmark-egui` | 6.9 MB binary | internal `ui_ready_ms` | 20.6 ms | n/a | 1 | `full_feature_warm_ms=597.7`. |
| Swift AppKit | `benchmark-appkit-macos` | 5.3 MB `.app` | `window_appeared_ms` | 95.8 ms median | 111.5 MB | 7 | New startup marker and generic process harness. |
| TypeScript TUI | `benchmark-tui` | n/a | snapshot `render_ms` | 133.5 ms median | n/a | 7 | Non-interactive terminal snapshot render. |
| SwiftUI macOS | `benchmark-swiftui-macos` | 9.3 MB `.app` | `window_appeared_ms` | 199.8 ms median | 115.4 MB | 7 | Native SwiftUI app release build. |
| Go Gio | `benchmark-gio-macos` | 6.6 MB binary | `firstFrameRenderedMs` | 281.2 ms median | 188.9 MB | 7 | Window configured at 8.7 ms median. |
| Qt 6/QML | `benchmark-qt-qml` | 0.4 MB binary | internal `ui_ready_ms` | 323.0 ms | n/a | 1 | Final clean smoke after fixing C++/QML build/runtime issues; `full_feature_warm_ms=345.0`. |
| Tauri WebUI shell | `benchmark-tauri-macos` | 118.6 MB `.app` | in-page render marker | 106.0 ms median | 100.3 MB | 7 | App setup 130.0 ms, window shown 364.5 ms, navigation finished 475.3 ms. |
| Dioxus WebUI shell | `benchmark-dioxus-macos` | 115.2 MB release dir | `windowShown_ms` | 468.0 ms median | 94.4 MB | 7 | Uses the WebUI backend bundle and exits after first reliable window marker. |
| Electron WebUI shell | `benchmark-electron-macos` | 270.5 MB `.app` | `webAppRendered_ms` | 483.6 ms median | 157.1 MB | 7 | Packaged Electron app with bundled WebUI resources. |
| C Raygui | `benchmark-raygui-c` | 1.1 MB binary | internal `ui_ready_ms` | 514.3 ms | n/a | 1 | `full_feature_warm_ms=235.0`; 5 data-source rows loaded. |
| Rust Raygui | `benchmark-raygui` | 2.3 MB binary | content-ready marker | 523.3 ms | n/a | 1 | First native Raygui content-ready marker. |
| Slint | `benchmark-slint` | 12.8 MB binary | internal `ui_ready_ms` | 450.9 ms | n/a | 1 | `full_feature_warm_ms=373.4`. |
| iOS SwiftUI simulator | `benchmark-ios-sim` | 15.1 MB `.app` | `window_appeared_ms` | 523.6 ms median | 295.5 MB | 7 | Simulator boot/install time excluded; samples start only after bootstatus/install complete. |
| Fyne | `benchmark-fyne-macos` | 23.0 MB binary | `firstFrameRenderedMs` | 584.6 ms median | 360.4 MB | 7 | Window configured at 233.6 ms median. |
| Compose Desktop | `benchmark-compose-desktop` | n/a | `ui_ready_ms` | 593.3 ms median | 108.3 MB | 7 | New Compose desktop marker and generic process harness. |
| WebView shell | `benchmark-webview-macos` | 109.5 MB `.app` | `webAppRendered_ms` | 597.2 ms median | 92.8 MB | 7 | Native WKWebView shell with bundled Node. |
| Flutter macOS | `benchmark-flutter-macos` | 40.3 MB `.app` | external content-ready marker | 628.7 ms median | 131.8 MB | 7 | Internal Dart marker median was 409.4 ms. |
| Objective-C AppKit | `benchmark-objc-appkit-macos` | 3.3 MB `.app` | `window_appeared_ms` | 750.3 ms median | 103.2 MB | 7 | New AppKit benchmark marker. |
| Python Toga/BeeWare | `benchmark-toga` | n/a | internal `ui_ready_ms` | 737.6 ms | n/a | 1 | Headless benchmark mode. |
| Android Compose emulator | `benchmark-android` | 16.3 MB APK | `ui_ready_ms` | 1225.8 ms median | 103.7 MB | 7 | Emulator boot/APK install time excluded; samples start only after device readiness and install complete. |
| Avalonia | `benchmark-avalonia` | n/a | `GFC_AVALONIA_FIRST_RENDER_MS` | 2263.9 ms | n/a | 1 | .NET 10.0.107 release run. |

## Target status

| Target | Result | Runtime | Notes |
| --- | --- | ---: | --- |
| `benchmark-swiftui-macos` | success | 41s | New generic process harness, 7 samples. |
| `benchmark-appkit-macos` | success | 14s | New Swift AppKit marker, 7 samples. |
| `benchmark-objc-appkit-macos` | success | 20s | New Objective-C AppKit marker, 7 samples. |
| `benchmark-ios-sim` | success after rerun | 21s focused mobile rerun | Initial install failed on symlinked resources, then stdout markers were unavailable; resource materialization and marker listener fixed it. Simulator boot/install setup is excluded from ready metrics. |
| `benchmark-webview-macos` | success | 14s | Existing shell metrics captured by generic process harness. |
| `benchmark-tauri-macos` | success after rerun | 26s rerun | Ready metric adjusted to the in-page marker exposed by current Tauri output. |
| `benchmark-electron-macos` | success after rerun | 16s rerun | Make target now resolves the packaged app path after packaging. |
| `benchmark-dioxus-macos` | success after rerun | 10s rerun | Uses `windowShown` as the reliable current marker. |
| `benchmark-nodegui` | success | 18s | Uses local `node_modules/.bin/qode`. |
| `benchmark-tui` | success | 12s | New non-interactive benchmark flag. |
| `benchmark-toga` | success | 1s | Existing headless target. |
| `benchmark-gio-macos` | success | 11s | Existing 7-sample harness. |
| `benchmark-fyne-macos` | success | 14s | Existing 7-sample harness. |
| `benchmark-textual` | success | <1s | Existing headless target. |
| `benchmark-tkinter` | success | 1s | Existing headless target. |
| `benchmark-wx` | success | <1s | Existing headless target. |
| `benchmark-flutter-macos` | success | 38s | Existing 7-sample harness. |
| `benchmark-gtk4` | success after rerun | 6s rerun | First full pass exposed Rust ownership/lifetime compile errors; fixed and reran. |
| `benchmark-slint` | success | 2s | Existing one-shot marker. |
| `benchmark-raygui` | success | 1s | Existing one-shot marker. |
| `benchmark-raygui-c` | success | 213s | First run populated/build raylib dependency. |
| `benchmark-imgui` | success | 2s | Existing one-shot marker. |
| `benchmark-iced` | success | 41s | Existing one-shot marker with benchmark output file. |
| `benchmark-makepad` | success | 25s | Existing one-shot marker. |
| `benchmark-egui` | success | 29s | Existing one-shot marker. |
| `benchmark-xilem-vello` | success | 9s | Existing headless/core marker. |
| `benchmark-gpui` | success | 9s | Existing headless/core marker. |
| `benchmark-imgui-cpp` | success | 21s | Existing one-shot marker. |
| `benchmark-qt-qml` | success after rerun | 1-sample smoke | First pass exposed C++ type mismatches and QML runtime issues; fixed and reran cleanly. |
| `benchmark-avalonia` | success | 9s | Existing .NET target now runnable because `dotnet` is installed. |
| `benchmark-compose-desktop` | success | 17s | New Compose Desktop benchmark marker and harness. |
| `benchmark-android` | success | 42s focused mobile rerun | New Android logcat harness with 7 samples on `gui_for_cli_api35`. Emulator launch/boot and APK install setup are excluded from ready metrics. |

## Benchmark infrastructure added or fixed

1. Added `scripts/benchmark-macos-process.py`, a reusable macOS harness for apps that print `*_ms` markers.
2. Added `scripts/benchmark-ios-sim.py`, including an HTTP marker listener for simulator apps and materialized iOS resource symlinks in the build targets.
3. Added `scripts/benchmark-android.py`, a logcat-based harness that can start an available AVD, install the APK, and collect repeated app-ready samples.
4. Added Makefile targets for SwiftUI macOS, Swift AppKit, Objective-C AppKit, iOS simulator, WebView, Tauri, Electron, Dioxus, NodeGui, TUI, Compose Desktop, and Android benchmarks.
5. Added benchmark markers to iOS SwiftUI, Swift AppKit, Objective-C AppKit, TypeScript TUI, Compose Desktop, Android Compose, and NodeGui.
6. Fixed GTK4 build errors now that the GTK stack is installed.
7. Fixed Qt/QML build/runtime issues exposed by the benchmark pass.

## Observations

1. The fastest full native GUI one-shot markers remain the immediate-mode/core renderers: C++ ImGui, Iced, Makepad, Rust ImGui, GTK4, and egui all reported under 25 ms internally.
2. The smallest successful binaries are Qt/QML at 0.4 MB for the executable, C Raygui at 1.1 MB, C++ ImGui at 1.3 MB, and the headless Xilem/GPUI binaries at 1.6 MB.
3. The web packagers have similar perceived startup ranges but very different footprint: WebView is 109.5 MB and 92.8 MB RSS, Tauri is 118.6 MB and 100.3 MB RSS, Electron is 270.5 MB and 157.1 MB RSS.
4. Mobile app startup inside already-running simulator/emulator instances is notably slower than desktop: iOS simulator reached first SwiftUI appearance at 523.6 ms median, while Android Compose reached 1225.8 ms median on the local emulator.
5. Android's focused mobile rerun had one cold outlier at 1968.7 ms; the final warm samples were around 1.1-1.3 s.
6. RSS is only captured by harnesses that keep the process alive long enough to sample it; one-shot internal benchmark modes generally do not report RSS yet.

## Remaining gaps

- Add RSS sampling to more one-shot native targets by running them through a common long-enough harness or adding a hold option.
- Make Qt/QML emit JSON or file output like the newer harnesses so reports do not depend on log parsing.
- Add browser-only Web UI benchmarking with a real browser/page-render marker if a headless browser dependency is adopted.
