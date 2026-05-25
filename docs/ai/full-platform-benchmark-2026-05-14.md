# Full platform benchmark run - 2026-05-14

Benchmarked on **2026-05-14 10:31-11:06 PDT** from local commit `5b558e7e6a4b26b4052b1c620e51dc3a0381dc83`.

Host: **macOS 26.4.1 (25E253)**, **Apple M1 Pro**, **arm64**, **32 GB RAM**. Toolchain snapshot: Swift 6.3.1, Xcode 26.4.1, Node 25.9.0, npm 11.12.1, Cargo 1.95.0, Go 1.26.3, Flutter 3.41.9, CMake 4.3.2, Gradle 9.5.1, .NET 10.0.107, GTK 4.22.4, Qt 6.11.0.

Raw logs were captured locally in `out/benchmark-runs/20260514-103128`, rerun folders `out/benchmark-runs/20260514-103128-rerun*`, and focused mobile rerun folder `out/benchmark-runs/20260514-124032-mobile-rerun`; they are intentionally not committed.

Mobile simulator/emulator boot and app installation time are setup phases, not startup metrics. The iOS and Android harnesses wait for the simulator/emulator to be ready before collecting samples, and their JSON output records setup time separately under `setup`.

## Scope

This pass attempted every platform surface available from this macOS checkout:

- Stable Apple and TypeScript surfaces: SwiftUI macOS, Web UI packagers, and TypeScript TUI.
- Experimental Apple, TypeScript, Rust, C, C++, Go, Python, .NET, Dart, and Kotlin surfaces.
- Mobile simulator/emulator surfaces available on macOS: iOS Simulator and Android Emulator.

Windows C#/WinUI and the PowerShell-only Windows Flutter benchmark were excluded because they are not runnable on macOS.

Only measurements that exercised a real user-facing window or terminal surface are included below. Bundle/core-only load checks are useful implementation tests, but they are not full-platform startup measurements and are excluded from the results table until they have real surface benchmarks.

## Successful measurements

| Surface | Target | Artifact size | Ready metric | Ready time | RSS | Samples | Notes |
| --- | --- | ---: | --- | ---: | ---: | ---: | --- |
| C++ Dear ImGui | `imgui-cpp` | 1.3 MB binary | internal `ui_ready_ms` | 4.3 ms | n/a | 1 | `full_feature_warm_ms=295.1`; 4 data-source rows loaded. |
| Iced | `iced` | 9.3 MB binary | internal `ui_ready_ms` | 16.5 ms | n/a | 1 | `full_feature_warm_ms=566.3`; 10 data-source rows loaded. |
| Makepad | `makepad` | 8.1 MB binary | internal `ui_ready_ms` | 18.8 ms | n/a | 1 | `full_feature_warm_ms=595.1`. |
| Rust Dear ImGui | `imgui` | 3.6 MB binary | internal `ui_ready_ms` | 19.1 ms | n/a | 1 | `full_feature_warm_ms=736.8`. |
| GTK4/libadwaita | `gtk4` | 1.9 MB binary | internal `ui_ready_ms` | 19.5 ms | n/a | 1 | GTK stack is installed on this host; build issues found by the first pass were fixed. |
| Rust egui | `egui` | 6.9 MB binary | internal `ui_ready_ms` | 20.6 ms | n/a | 1 | `full_feature_warm_ms=597.7`. |
| Swift AppKit | `appkit-macos` | 5.3 MB `.app` | `window_appeared_ms` | 95.8 ms median | 111.5 MB | 7 | New startup marker and generic process harness. |
| TypeScript TUI | `tui` | n/a | snapshot `render_ms` | 133.5 ms median | n/a | 7 | Non-interactive terminal snapshot render. |
| SwiftUI macOS | `swiftui-macos` | 9.3 MB `.app` | `window_appeared_ms` | 199.8 ms median | 115.4 MB | 7 | Native SwiftUI app release build. |
| Go Gio | `gio` | 6.6 MB binary | `firstFrameRenderedMs` | 281.2 ms median | 188.9 MB | 7 | Window configured at 8.7 ms median. |
| Python Textual | `textual` | n/a | `ui_ready_ms` | 291.3 ms | 78.6 MB | 1 | Real terminal UI surface via generic process harness. |
| Rust GPUI | `gpui` | 6.1 MB binary | `ui_ready_ms` | 161.4 ms | 64.8 MB | 1 | Real GPUI window after installing the Metal toolchain. |
| Qt 6/QML | `qt-qml` | 0.4 MB binary | internal `ui_ready_ms` | 323.0 ms | n/a | 1 | Final clean smoke after fixing C++/QML build/runtime issues; `full_feature_warm_ms=345.0`. |
| Python Tkinter | `tkinter` | n/a | `ui_ready_ms` | 413.9 ms | 184.5 MB | 1 | Real Tk window surface via generic process harness. |
| Tauri WebUI shell | `tauri` | 118.6 MB `.app` | in-page render marker | 106.0 ms median | 100.3 MB | 7 | App setup 130.0 ms, window shown 364.5 ms, navigation finished 475.3 ms. |
| Dioxus WebUI shell | `dioxus` | 115.2 MB release dir | `windowShown_ms` | 468.0 ms median | 94.4 MB | 7 | Uses the WebUI backend bundle and exits after first reliable window marker. |
| Electron WebUI shell | `electron` | 270.5 MB `.app` | `webAppRendered_ms` | 483.6 ms median | 157.1 MB | 7 | Packaged Electron app with bundled WebUI resources. |
| C Raygui | `raygui-c` | 1.1 MB binary | internal `ui_ready_ms` | 514.3 ms | n/a | 1 | `full_feature_warm_ms=235.0`; 5 data-source rows loaded. |
| Rust Raygui | `raygui` | 2.3 MB binary | content-ready marker | 523.3 ms | n/a | 1 | First native Raygui content-ready marker. |
| Slint | `slint` | 12.8 MB binary | internal `ui_ready_ms` | 450.9 ms | n/a | 1 | `full_feature_warm_ms=373.4`. |
| iOS SwiftUI simulator | `ios-swiftui-simulator` | 15.1 MB `.app` | `window_appeared_ms` | 523.6 ms median | 295.5 MB | 7 | Simulator boot/install time excluded; samples start only after bootstatus/install complete. |
| Fyne | `fyne` | 23.0 MB binary | `firstFrameRenderedMs` | 584.6 ms median | 360.4 MB | 7 | Window configured at 233.6 ms median. |
| Python wxPython | `wx` | n/a | `ui_ready_ms` | 584.5 ms | 158.8 MB | 1 | Real wxPython window surface via generic process harness. |
| Compose Desktop | `compose-desktop` | n/a | `ui_ready_ms` | 593.3 ms median | 108.3 MB | 7 | New Compose desktop marker and generic process harness. |
| WebView shell | `webview-shell` | 109.5 MB `.app` | `webAppRendered_ms` | 597.2 ms median | 92.8 MB | 7 | Native WKWebView shell with bundled Node. |
| Flutter macOS | `flutter` | 40.3 MB `.app` | external content-ready marker | 628.7 ms median | 131.8 MB | 7 | Internal Dart marker median was 409.4 ms. |
| Rust Xilem/Vello | `xilem-vello` | 12 MB binary | `ui_ready_ms` | 690.2 ms | 82.0 MB | 1 | Real Xilem/Vello window surface via generic process harness. |
| Objective-C AppKit | `objc-appkit-macos` | 3.3 MB `.app` | `window_appeared_ms` | 750.3 ms median | 103.2 MB | 7 | New AppKit benchmark marker. |
| Python Toga/BeeWare | `toga` | n/a | `ui_ready_ms` | 1011.9 ms | 197.3 MB | 1 | Real Toga window surface; output includes a Toga `Pack.padding` deprecation warning. |
| Android Compose emulator | `android-compose` | 16.3 MB APK | `ui_ready_ms` | 1225.8 ms median | 103.7 MB | 7 | Emulator boot/APK install time excluded; samples start only after device readiness and install complete. |
| Avalonia | `avalonia` | n/a | `GFC_AVALONIA_FIRST_RENDER_MS` | 2263.9 ms | n/a | 1 | .NET 10.0.107 release run. |

## Target status

| Target | Result | Runtime | Notes |
| --- | --- | ---: | --- |
| `swiftui-macos` | success | 41s | New generic process harness, 7 samples. |
| `appkit-macos` | success | 14s | New Swift AppKit marker, 7 samples. |
| `objc-appkit-macos` | success | 20s | New Objective-C AppKit marker, 7 samples. |
| `ios-swiftui-simulator` | success after rerun | 21s focused mobile rerun | Initial install failed on symlinked resources, then stdout markers were unavailable; resource materialization and marker listener fixed it. Simulator boot/install setup is excluded from ready metrics. |
| `webview-shell` | success | 14s | Existing shell metrics captured by generic process harness. |
| `tauri` | success after rerun | 26s rerun | Ready metric adjusted to the in-page marker exposed by current Tauri output. |
| `electron` | success after rerun | 16s rerun | Make target now resolves the packaged app path after packaging. |
| `dioxus` | success after rerun | 10s rerun | Uses `windowShown` as the reliable current marker. |
| `nodegui` | success | 18s | Uses local `node_modules/.bin/qode`. |
| `tui` | success | 12s | New non-interactive benchmark flag. |
| `toga` | success | 1-sample follow-up | Real Toga window surface marker via generic process harness. |
| `gio` | success | 11s | Existing 7-sample harness. |
| `fyne` | success | 14s | Existing 7-sample harness. |
| `textual` | success | 1-sample follow-up | Real Textual terminal surface marker via generic process harness. |
| `tkinter` | success | 1-sample follow-up | Real Tk window surface marker via generic process harness. |
| `wx` | success | 1-sample follow-up | Real wxPython window surface marker via generic process harness. |
| `flutter` | success | 38s | Existing 7-sample harness. |
| `gtk4` | success after rerun | 6s rerun | First full pass exposed Rust ownership/lifetime compile errors; fixed and reran. |
| `slint` | success | 2s | Existing one-shot marker. |
| `raygui` | success | 1s | Existing one-shot marker. |
| `raygui-c` | success | 213s | First run populated/build raylib dependency. |
| `imgui` | success | 2s | Existing one-shot marker. |
| `iced` | success | 41s | Existing one-shot marker with benchmark output file. |
| `makepad` | success | 25s | Existing one-shot marker. |
| `egui` | success | 29s | Existing one-shot marker. |
| `xilem-vello` | success | 1-sample follow-up | Real Xilem/Vello window surface marker via generic process harness. |
| `gpui` | success | 1-sample follow-up | Real GPUI window surface marker via generic process harness. |
| `imgui-cpp` | success | 21s | Existing one-shot marker. |
| `qt-qml` | success after rerun | 1-sample smoke | First pass exposed C++ type mismatches and QML runtime issues; fixed and reran cleanly. |
| `avalonia` | success | 9s | Existing .NET target now runnable because `dotnet` is installed. |
| `compose-desktop` | success | 17s | New Compose Desktop benchmark marker and harness. |
| `android-compose` | success | 42s focused mobile rerun | New Android logcat harness with 7 samples on `gui_for_cli_api35`. Emulator launch/boot and APK install setup are excluded from ready metrics. |

## Benchmark infrastructure added or fixed

1. Added `tools/benchmarking/macos_process.py`, a reusable macOS harness for apps that print `*_ms` markers.
2. Added `tools/benchmarking/ios_sim.py`, including an HTTP marker listener for simulator apps and materialized iOS resource symlinks in the build targets.
3. Added `tools/benchmarking/android.py`, a logcat-based harness that can start an available AVD, install the APK, and collect repeated app-ready samples.
4. Added Makefile targets for SwiftUI macOS, Swift AppKit, Objective-C AppKit, iOS simulator, WebView, Tauri, Electron, Dioxus, NodeGui, TUI, Compose Desktop, and Android benchmarks.
5. Added benchmark markers to iOS SwiftUI, Swift AppKit, Objective-C AppKit, TypeScript TUI, Compose Desktop, Android Compose, and NodeGui.
6. Fixed GTK4 build errors now that the GTK stack is installed.
7. Fixed Qt/QML build/runtime issues exposed by the benchmark pass.
8. Replaced Python Toga/Textual/Tkinter/wxPython, Rust Xilem/Vello, and Rust GPUI load-only benchmark paths with real terminal or window surface markers.

## Observations

1. The fastest accepted full native GUI one-shot markers remain C++ ImGui, Iced, Makepad, Rust ImGui, GTK4, and egui; all reported under 25 ms internally.
2. The smallest successful binaries are Qt/QML at 0.4 MB for the executable, C Raygui at 1.1 MB, and C++ ImGui at 1.3 MB.
3. The web packagers have similar perceived startup ranges but very different footprint: WebView is 109.5 MB and 92.8 MB RSS, Tauri is 118.6 MB and 100.3 MB RSS, Electron is 270.5 MB and 157.1 MB RSS.
4. Mobile app startup inside already-running simulator/emulator instances is notably slower than desktop: iOS simulator reached first SwiftUI appearance at 523.6 ms median, while Android Compose reached 1225.8 ms median on the local emulator.
5. Android's focused mobile rerun had one cold outlier at 1968.7 ms; the final warm samples were around 1.1-1.3 s.
6. RSS is only captured by harnesses that keep the process alive long enough to sample it; one-shot internal benchmark modes generally do not report RSS yet.

## Remaining gaps

- Historical rows above reflect the original local run and have not been numerically regenerated. The benchmark targets now emit JSON payloads with startup medians, process-tree peak RSS, launcher metadata, and artifact sizing for the next full run.
- Use `make benchmark ARGS='macos'` to run every visible UX benchmark command runnable from macOS, or `make benchmark ARGS='benchmark-all'` to include the Windows Flutter benchmark wrapper as well. Mobile boot/install setup remains recorded separately and excluded from startup metrics.
- Browser-only Web UI now has `webui`, which launches Chromium and waits for the page's `gui-for-cli-rendered` event.
- Interpreted/dev-run surfaces without a standalone distributable binary report their renderer/source artifact footprint plus launcher metadata rather than a packaged app size.
- Mojo is still a core-renderer benchmark, not a real UI surface benchmark.
