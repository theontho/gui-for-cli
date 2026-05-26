# Platform implementation difficulty subreports

This report summarizes implementation difficulty from the local Copilot session history plus the committed benchmark documentation. It is meant to support the platform lessons article, not replace the raw benchmark reports.

Primary committed sources:

- `docs/ai/benchmark-findings.md`
- `docs/ai/macos-benchmark-and-screenshot-run-2026-05-15.md`
- `docs/ai/full-platform-benchmark-2026-05-14.md`
- `docs/ai/gui-toolkit-macos-benchmark-run.md`
- `docs/ai/windows-benchmark-summary.md`
- `docs/desktop-gui-experiments.md`

Local-only session evidence was read from `~/.copilot/session-state`. Those logs are not committed. The useful signals were session duration, checkpoint count, repeated "not complete" follow-ups, number of validation/rerun cycles, toolchain blockers, and whether the implementation reached realistic WGSExtract workflow parity.

## Scoring rubric

| Score | Meaning |
| ---: | --- |
| 1 | Straightforward. Single-pass or mostly wiring existing behavior. |
| 2 | Manageable. Some platform details, but few deep rewrites. |
| 3 | Moderate. Multiple missing features or benchmark/instrumentation fixes. |
| 4 | Hard. Deep parity work, runtime rewrites, CI/toolchain issues, or major UX gaps. |
| 5 | Very hard. Long multi-session effort with repeated audits, blockers, or still-incomplete parity. |

Completeness is scored separately: 5 means product-like for the WGSExtract workflow; 1 means a narrow benchmark/core prototype. Visual effectiveness is the user's 1-5 rating of the regenerated screenshot set exported on 2026-05-26, normalized so reference implementations are anchors and WebUI shells share one UX rating.

## Summary table

| Surface | Difficulty | Completeness | Visual | Main evidence |
| --- | ---: | ---: | --- | --- |
| SwiftUI macOS | 3 | 5 | Reference | Startup fix showed the platform was not the problem; synchronous bundle/workspace/config/setup work was. After deferral and idempotent workspace sync, first-window/content-ready markers improved into the low hundreds of ms. |
| Tauri WebUI | 4 | 5 | WebUI shell family | Complete because it reused WebUI, but packaging was non-trivial: bundled Node, resource resolution, updater/signing/installer work, WebView/WebView2 memory, and platform-specific release validation. |
| Native Windows C# | 3 | 4 | n/a | Strong Windows benchmark result, especially NativeAOT. Difficulty is mostly packaging/installer/toolchain rather than UI model reconstruction. |
| WebUI reference | 2 | 5 | Reference | Easiest complete visual surface because it is the reference WebUI. Cold-browser product UX is poor, but implementation difficulty is low. |
| Browser WebUI / Electron / WKWebView shell | 2-3 | 4-5 | WebUI shell family | UX-equivalent to the WebUI reference; differences are packaging, startup, memory, process lifecycle, updates, and platform integration. |
| TypeScript TUI | 2 | 3 | 3 | Low runtime overhead and straightforward terminal rendering, but intentionally not a desktop GUI parity target. |
| Flutter | 5 | 4 | 4 | Long deep-parity effort. Required config/state IO, data sources, action rules, setup execution, path picking, terminal tabs, RTL, semantics, file splits, Flutter analysis/tests, and push/toolchain fixes. |
| Gio | 4 | 3 | 2 | Small and fast, but user still found it incomplete after first parity work. Required custom schema/runtime/UI, path pickers, data-source execution, action logic, persistence, and still lacked rich terminal/sidebar/settings parity. |
| Slint | 5 | 3 | 2 | Excellent benchmark signals but deep parity remained difficult. Slint-specific constraints, large in-progress plan, process hardening, terminal tabs, state/config/data-source work, and many known remaining gaps. |
| Rust Raygui | 4 | 3 | 2 | Fast and small, but required substantial custom runtime, layout, terminal, data source, path picker, and spec work. Accessibility remains inherently limited by raylib/raygui. |
| C Raygui | 4 | 3 | 2 | Initial speed was good, but feature parity caused C memory/runtime complexity, CMake dependency issues, file-size refactors, partial TOML support, and compile failures after refactor. |
| Rust ImGui | 3 | 2 | 2 | Very fast internal markers and small package, but immediate-mode app parity is limited. Useful as a benchmark more than a product shell. |
| C++ ImGui | 4 | 3 | 2 | Very strong size/startup metrics, but parity gaps remained: config persistence, setup actions, confirmations, checkbox groups, and benchmark semantics. |
| Swift AppKit | 5 | 3 | 4 | Native and fast, but full generic bundle UI was fragile. A later layout/rename pass produced a blank/broken content tree despite build success and AX smoke caveats. |
| ObjC AppKit | 4 | 3 | 2 | Small/fast native experiment, but no reliable ready hook initially and later spec work needed config/data-source/row-action plumbing. |
| Dioxus WebUI | 3 | 3 | 2 | Smaller WebUI shell benchmark, but instrumentation did not reach final rendered completion in some runs. |
| NodeGui/Qt | 4 | 3 | 1 | Shared TypeScript idea was appealing, but package payload was very large and instrumentation/memory required separate handling. |
| Qt/QML | 4 | 3 | 3 | Full benchmark pass exposed C++ type mismatches, QML runtime conflicts, recursive controls, and layout property issues before it ran cleanly. |
| GTK4/libadwaita | 3 | 3 | 2 | Benchmark pass found Rust GTK ownership/lifetime errors and the screenshot harness needed a software-renderer capture fix. |
| Python Tkinter/wx/Toga/Textual | 3 | 2 | 3-4 | Moving from headless/core shortcuts to real UI markers required dependency setup, PEP 668 workaround, stderr metrics for Textual, and harness changes. |
| iOS Simulator / Android Compose | 4 | 3 | 3 | Real mobile app markers worked, but simulator/emulator boot/install had to be separated from startup metrics; iOS needed materialized resources and HTTP marker collection. |
| Compose Desktop | 4 | 3 | 4 | Looked visually promising, but JVM/Gradle startup and desktop packaging keep it in the research set for now. |

## Active-time session evidence

The first pass used raw wall-clock spans from checkpoint metadata. That overstated several efforts because long sessions included overnight gaps, waiting for external checks, or idle time between user follow-ups. This revision scanned local `~/.copilot/session-state` checkpoint folders and `events.jsonl` files, then cross-checked recent `gui-for-cli` and `wgsextract-cli` sessions in the cloud session store.

The active-time estimate sums time between adjacent session events, capped at 30 minutes per gap. That keeps long builds and CI waits visible, but prevents a four-hour idle gap from counting as four hours of implementation. The table below is overlapping by design: release/updater work and WGSExtract bundle work supported multiple UI shells, so those sessions are separated from the per-toolkit implementation rows.

| Category | Sessions counted | Active time | Wall span | Difficulty signal |
| --- | ---: | ---: | ---: | --- |
| Reference WebUI/WGS behavior | 4 | 12.2 h | 13.1 h | Building the reusable behavior model, generic bundle loader, dynamic WGS controls, setup state, terminal behavior, localization, and WebUI polish was a real product effort. WebUI shells inherit this work rather than reimplementing it. |
| SwiftUI/reference macOS | 5 | 10.2 h | 30.5 h | The native reference took meaningful work, but much of the apparent duration was idle. The hard part was app-specific startup/resource/workspace behavior, not SwiftUI itself. |
| Tauri/Electron/WKWebView packaging | 5 | 19.7 h | 45.9 h | The shared WebUI made UX complete, but packaging was substantial: bundled Node/resource paths, app identity, updater behavior, signing, launch validation, and memory/process tradeoffs. |
| Flutter | 1 | 8.2 h | 22.5 h | Deep parity audit and implementation work remained significant after idle correction: config/state IO, data sources, setup/action lifecycle, terminal tabs, RTL/accessibility, tests, and benchmarking. |
| React Native | 1 | 7.3 h | 20.9 h | Similar to Flutter: first-pass parity looked useful but was later judged incomplete, requiring deeper shell, terminal, cancellation, and control parity work. Not part of the current screenshot corpus. |
| Slint | 1 | 7.6 h | 22.5 h | Strong benchmark signals, but deep parity remained costly because much of the runtime and UI behavior had to be rebuilt in Slint/Rust. |
| Gio | 2 | 9.5 h | 24.1 h | Lightweight and fast, but took more active implementation time than its prototype appearance suggested and still felt incomplete after initial parity. |
| Kotlin Compose / Android | 1 | 6.4 h | 13.3 h | Required shared Kotlin runtime, Android packaging/assets, Compose Desktop, Gradle/JDK/Android SDK setup, and multiple validation/debug loops. |
| New renderer batch: egui, iced, Qt/QML, Avalonia, GTK4, Fyne, Makepad | 1 orchestrating session | 8.0 h | 15.5 h | A parallel batch was efficient per renderer, but orchestration, PR review, CI, toolchain blockers, and repeated CodeRabbit fixes made this a substantial platform-expansion effort. |
| Rust Raygui | 1 | 4.5 h | 4.9 h | Fast focused prototype, but product parity was constrained by custom layout/runtime work and accessibility limits. |
| C Raygui | 1 | 2.4 h | 2.7 h | Quick initial port, but C memory/runtime and CMake issues made deeper parity fragile. |
| Rust ImGui | 1 | 2.3 h | 3.9 h | Relatively quick renderer benchmark; low active time reflects limited product parity rather than a complete app. |
| C++ ImGui | 1 | 4.2 h | 7.0 h | Strong benchmark result, but parity gaps and native C++ plumbing made it more work than Rust ImGui. |
| Swift AppKit | 1 | 4.4 h | 20.1 h | Raw duration was mostly idle; active work still showed hand-built AppKit generic UI was layout-heavy and fragile compared with SwiftUI. |
| ObjC AppKit | 1 | 4.6 h | 20.4 h | Similar active effort to Swift AppKit, with extra Objective-C runtime/category plumbing and ready-hook/instrumentation work. |
| Benchmark/screenshot harness and reports | 6 | 31.0 h | 92.5 h | The largest supporting effort after idle correction. Real-window benchmarking, screenshot capture, platform-specific launch fixes, and reporting took more active time than most individual toolkit implementations. |
| Release/updater/installer packaging | 7 | 47.9 h | 78.0 h | The biggest non-UI implementation bucket: Sparkle/Tauri updater work, signing identities, DMGs, release staging, installer behavior, and PR/CI follow-up. |
| `wgsextract-cli` and bundle integration | 14 | 36.9 h | 73.7 h | The CLI and bundle work materially shaped GUI difficulty: real downloads, progress, installers, release versions, WGS command behavior, site updates, and realistic data paths made the GUI task product-like rather than toy-like. |

Recent cloud-only sessions showed the same pattern at smaller scale. For example, a recent update-mechanism session had 5.56 h of turn-capped active time across a 22.76 h wall span, while the current screenshot-rating/article session had 1.42 h active across 2.24 h wall by turn timestamps. Those were used as cross-checks, but local event logs provide finer-grained active estimates for the older platform work.

## Lessons by implementation pattern

### Reusing a complete renderer/runtime wins

WebUI-derived shells were easiest to make complete because the hard behavior already existed. Browser WebUI, Tauri, Electron, and WKWebView mostly differed in packaging, process lifecycle, and memory footprint, not in the UX they rendered.

### Native product shells need platform-specific focus

SwiftUI and Windows C# won where the product matched the platform. Their work was not free, but it was coherent: keep native integration, fix startup/process issues, and package like a platform app.

### Cross-platform native renderers need deep parity investment

Flutter, Gio, and Slint were promising because they can render native-looking app surfaces without browser processes. The cost was rebuilding every GUI for CLI behavior in each toolkit. That made them expensive until a shared runtime model covered more of the workflow.

### Immediate-mode renderers are benchmark gold, product expensive

Raygui and ImGui are excellent for discovering lower bounds on package size, startup, and drawing overhead. They are less good as default product shells because accessibility, native controls, rich layout, terminal UX, and platform affordances become custom work.

### "Full surface" beats "headless benchmark"

The benchmark sessions repeatedly rejected headless/core shortcuts. A platform only belongs in user-facing comparison tables when it opens a real window or terminal UI and measures a real readiness marker.

## Current recommendation

Use:

1. `swiftui-macos` for the primary Apple product app.
2. Native Windows C# for the primary Windows-native app direction.
3. `tauri-webui` for the portable packaged WebUI, chosen from the UX-equivalent WebUI shell family for packaging and distribution reasons.
4. WebUI browser mode for development/preview.
5. TypeScript TUI for terminal-first workflows.
6. Flutter, Gio, Slint, Raygui, ImGui, AppKit variants, Dioxus, NodeGui, Qt/QML, GTK4, Python UIs, and mobile as research until each has full workflow parity and visual review evidence.

## Visual effectiveness scoring

The user rated the regenerated screenshot set with the temporary rater and exported a 2026-05-26 visual-effectiveness ratings JSON file. The raw export covers 34 screenshots, averages 2.91/5, and has a median score of 3/5.

For conclusions, the report normalizes those raw scores in two ways:

1. SwiftUI macOS and WebUI are reference implementations, not experimental competitors.
2. Browser WebUI, Tauri WebUI, Electron WebUI, and WKWebView shell are one WebUI shell UX family because they render the same interface. Their meaningful differences are packaging, startup, memory, updates, and platform integration.

After excluding the two reference anchors and merging the WebUI shell family, the comparable experimental set has 29 visual units, averages 2.55/5, and has a median score of 2/5.

| Score | Surfaces |
| ---: | --- |
| Reference | SwiftUI macOS, WebUI |
| 5 | WebUI shell family: Browser WebUI, Tauri WebUI, Electron WebUI, WKWebView shell |
| 4 | Compose Desktop, Flutter, Python wxPython, Swift AppKit |
| 3 | Android Compose, Fyne, iOS SwiftUI Simulator, Python Textual, Python Tkinter, Python Toga, Qt/QML, TypeScript TUI |
| 2 | C Raygui, C++ Dear ImGui, Dioxus WebUI, Go Gio, GPUI, GTK4/libadwaita, Iced, Makepad, Objective-C AppKit, Rust Dear ImGui, Rust egui, Rust Raygui, Slint |
| 1 | Avalonia, NodeGui, Xilem/Vello |

Detailed raw exported scores, preserved for traceability:

| Surface | Screenshot | Score | Notes |
| --- | --- | ---: | --- |
| Android Compose | `android-compose.png` | 3 |  |
| Swift AppKit | `appkit-macos.png` | 4 |  |
| Avalonia | `avalonia.png` | 1 |  |
| Browser Web UI | `browser-webui.png` | 5 | WebUI shell family; UX-equivalent to Tauri, Electron, and WKWebView. |
| Compose Desktop | `compose-desktop.png` | 4 |  |
| Dioxus WebUI | `dioxus.png` | 2 |  |
| Rust egui | `egui.png` | 2 |  |
| Electron WebUI | `electron.png` | 5 | WebUI shell family; UX-equivalent to Browser WebUI, Tauri, and WKWebView. Export note preserved from the rating pass: loading spinner, not captured properly, probably identical to webui. The screenshot harness now waits for Electron's WebUI-rendered marker before capture. |
| Flutter | `flutter.png` | 4 |  |
| Fyne | `fyne.png` | 3 |  |
| Go Gio | `gio.png` | 2 |  |
| GPUI | `gpui.png` | 2 |  |
| GTK4/libadwaita | `gtk4.png` | 2 | Export note preserved from the rating pass: GTK4/libadwaita is a black screen, was not captured properly. The screenshot harness now forces GTK's Cairo renderer before capture. |
| Iced | `iced.png` | 2 |  |
| Rust Dear ImGui | `imgui.png` | 2 |  |
| C++ Dear ImGui | `imgui-cpp.png` | 2 |  |
| iOS SwiftUI Simulator | `ios-swiftui-simulator.png` | 3 |  |
| Makepad | `makepad.png` | 2 |  |
| NodeGui | `nodegui.png` | 1 |  |
| Objective-C AppKit | `objc-appkit-macos.png` | 2 |  |
| Qt/QML | `qt-qml.png` | 3 |  |
| C Raygui | `raygui-c.png` | 2 |  |
| Rust Raygui | `raygui.png` | 2 |  |
| Slint | `slint.png` | 2 |  |
| SwiftUI macOS | `swiftui-macos.png` | 5 | Reference implementation; not counted as an experimental visual competitor. |
| Tauri WebUI | `tauri.png` | 5 | WebUI shell family; UX-equivalent to Browser WebUI, Electron, and WKWebView. |
| Python Textual | `textual.png` | 3 |  |
| Python Tkinter | `tkinter.png` | 3 |  |
| Python Toga | `toga.png` | 3 |  |
| TypeScript TUI | `tui.png` | 3 |  |
| WebUI | `webui.png` | 5 | Reference implementation; WebUI shell scores inherit this UX. |
| WKWebView shell | `webview-shell.png` | 5 | WebUI shell family; UX-equivalent to Browser WebUI, Tauri, and Electron. |
| Python wxPython | `wx.png` | 4 |  |
| Xilem/Vello | `xilem-vello.png` | 1 |  |
