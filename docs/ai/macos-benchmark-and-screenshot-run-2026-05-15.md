# macOS benchmark and screenshot run - 2026-05-15

Commands run:

```bash
make benchmark ARGS='benchmark macos'
make benchmark ARGS='screenshot macos'
make benchmark ARGS='benchmark ios-sim android flutter-macos'
make benchmark ARGS='screenshot browser-webui'
```

The visible UX benchmark suite completed and produced 33 UX benchmark rows. The browser Web UI payload reports `headless: false`, so Chromium was shown as a real UX surface. The screenshot suite completed and refreshed 33 PNGs under `docs/ai/screenshots`.

Primary readiness metrics vary by surface. See each JSON payload for the full median set, launcher metadata, artifact list, and per-run samples.

| Surface | Platform / language | JSON | Readiness ms | Readiness metric | RSS MB | Artifact MB |
| --- | --- | --- | ---: | --- | ---: | ---: |
| C++ Dear ImGui | macOS / C++ | `out/release/imgui-cpp/benchmark.json` | 3.6 | UI ready | 10.0 | 1.409 |
| GTK4/libadwaita | macOS / Rust | `out/release/gtk4/benchmark.json` | 19.6 | UI ready | 14.6 | 2.036 |
| Rust Dear ImGui | macOS / Rust | `out/release/imgui/benchmark.json` | 19.6 | UI ready | 11.4 | 3.781 |
| Iced | macOS / Rust | `out/release/iced/benchmark.json` | 20.5 | UI ready | 11.6 | 9.762 |
| Rust egui | macOS / Rust | `out/release/egui/benchmark.json` | 20.7 | UI ready | 11.4 | 7.218 |
| Makepad | macOS / Rust | `out/release/makepad/benchmark.json` | 21.0 | UI ready | 11.3 | 8.525 |
| Browser Web UI | browser / TypeScript | `out/release/webui-browser/benchmark.json` | 41.5 | web app rendered | 1048.0 | 0.660 |
| Tauri WebUI macOS | macOS / TypeScript + Rust | `out/release/tauri/benchmark-macos.json` | 44.0 | web app rendered | 172.5 | 123.985 |
| Swift AppKit macOS | macOS / Swift | `out/release/appkit/benchmark-macos.json` | 102.9 | window appeared | 112.7 | 5.548 |
| TypeScript TUI | terminal / TypeScript | `out/release/tui/benchmark.json` | 189.9 | render | 66.4 | 0.112 |
| SwiftUI macOS | macOS / Swift | `out/release/swift/benchmark-macos.json` | 196.6 | window appeared | 116.1 | 9.753 |
| Rust GPUI | macOS / Rust | `out/release/gpui/benchmark.json` | 217.5 | UI ready | 74.8 | 6.391 |
| Python Textual | terminal / Python | `out/release/textual/benchmark.json` | 256.2 | UI ready | 82.6 | 0.219 |
| Qt 6/QML | macOS / C++ + QML | `out/release/qt-qml/benchmark.json` | 321.0 | UI ready | 95.7 | 0.448 |
| Go Gio | macOS / Go | `out/release/gio/benchmark-macos.json` | 332.5 | first frame | 208.4 | 6.961 |
| Slint | macOS / Rust | `out/release/slint/benchmark.json` | 429.0 | UI ready | 31.3 | 13.388 |
| C Raygui | macOS / C | `out/release/raygui-c/benchmark.json` | 452.7 | UI ready | 85.9 | 1.118 |
| Dioxus WebUI macOS | macOS / Rust | `out/release/dioxus/benchmark-macos.json` | 460.9 | window shown | 159.7 | 120.455 |
| Electron WebUI macOS | macOS / TypeScript | `out/release/electron/benchmark-macos.json` | 496.7 | web app rendered | 537.1 | 282.321 |
| iOS Simulator | iOS Simulator / Swift | `out/release/ios-sim/benchmark-macos.json` | 533.3 | window appeared | 295.0 | 15.656 |
| Rust Raygui | macOS / Rust | `out/release/raygui/benchmark.json` | 568.8 | content ready | 90.8 | 2.387 |
| WebView shell macOS | macOS / Swift + TypeScript | `out/release/webview/benchmark-macos.json` | 573.9 | web app rendered | 93.1 | 114.459 |
| Fyne | macOS / Go | `out/release/fyne/benchmark-macos.json` | 591.8 | first frame | 360.5 | 24.107 |
| Compose Desktop | macOS / Kotlin | `out/release/compose-desktop/benchmark-macos.json` | 602.4 | UI ready | 107.6 | 0.584 |
| Flutter macOS | macOS / Dart | `out/release/flutter/benchmark-macos.json` | 635.8 | external content ready | 132.4 | 42.206 |
| Objective-C AppKit macOS | macOS / Objective-C | `out/release/objc-appkit/benchmark-macos.json` | 647.1 | window appeared | 105.8 | 3.282 |
| NodeGui macOS | macOS / TypeScript + NodeGui | `out/release/nodegui/benchmark-macos.json` | 713.3 | window shown | 277.8 | 0.064 |
| Python wxPython | macOS / Python | `out/release/wx/benchmark.json` | 718.4 | UI ready | 167.2 | 0.179 |
| Python Tkinter | macOS / Python | `out/release/tkinter/benchmark.json` | 789.7 | UI ready | 207.0 | 0.182 |
| Rust Xilem/Vello | macOS / Rust | `out/release/xilem-vello/benchmark.json` | 849.4 | UI ready | 107.0 | 12.827 |
| Python Toga | macOS / Python | `out/release/toga/benchmark.json` | 1003.1 | UI ready | 200.7 | 0.236 |
| Avalonia | macOS / C# | `out/release/avalonia/benchmark.json` | 1210.4 | first render | 187.0 | 109.759 |
| Android | Android Emulator / Kotlin | `out/release/android/benchmark.json` | 10338.2 | UI ready | 102.8 | 17.145 |

Notes:

- Mojo is intentionally excluded from the visible UX table and `make benchmark ARGS='benchmark macos'`; `make benchmark ARGS='benchmark mojo-core'` remains available as a separate core-renderer benchmark.
- Mobile simulator/emulator boot and install work is setup for this run; startup/readiness metrics measure the app surface after that setup.
- The Toga benchmark target now writes to `out/release/toga/benchmark.json` so all macOS aggregate benchmark payloads are under `out/release`.
- NodeGui screenshots now launch with `--no-setup`, and the NodeGui app enters the Qt event loop after showing the window so macOS exposes it for capture.
- Android, iOS Simulator, and Flutter benchmark payloads now include raw `name` metadata.
- Browser Web UI now has its own visible screenshot at `docs/ai/screenshots/browser-webui.png`.

## Screenshots

| Screenshot | Dimensions |
| --- | ---: |
| `android-emulator.png` | 1080x2400 |
| `avalonia.png` | 2496x1760 |
| `browser-webui.png` | 1344x864 |
| `compose-desktop.png` | 2912x1952 |
| `cpp-imgui.png` | 2584x1808 |
| `dioxus.png` | 2824x1928 |
| `egui.png` | 2584x1808 |
| `electron.png` | 2624x1824 |
| `flutter-macos.png` | 2824x1864 |
| `fyne.png` | 3104x2128 |
| `gio.png` | 3104x2128 |
| `gpui.png` | 2024x1570 |
| `gtk4.png` | 2704x1784 |
| `iced.png` | 2584x1808 |
| `ios-simulator.png` | 1206x2622 |
| `makepad.png` | 2184x1672 |
| `nodegui.png` | 2624x1692 |
| `objc-appkit.png` | 2584x1928 |
| `python-textual.png` | 3824x2384 |
| `python-tkinter.png` | 2584x1848 |
| `python-toga.png` | 2378x1508 |
| `python-wxpython.png` | 2496x1696 |
| `qt-qml.png` | 2912x2016 |
| `raygui-c.png` | 2464x1728 |
| `raygui.png` | 2464x1728 |
| `rust-imgui.png` | 2584x1808 |
| `slint.png` | 2464x1728 |
| `swift-appkit.png` | 2424x1808 |
| `swiftui-macos.png` | 1936x2236 |
| `tauri.png` | 2624x1824 |
| `typescript-tui.png` | 3824x2384 |
| `webview.png` | 2536x1800 |
| `xilem-vello.png` | 2784x1968 |
