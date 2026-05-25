---
output: 'experiments.html'
title: 'GUI for CLI experiments and results'
description: 'Desktop GUI experiments, benchmark lessons, and why swiftui-macos and tauri-webui remain the product frontends.'
eyebrow: 'Research results'
heading: 'Many experiments, two product frontends.'
lede: 'GUI for CLI tried native, WebView, browser, terminal, and cross-platform GUI stacks against real bundle requirements. The experiments remain valuable research, but they do not expand the supported frontend list.'
actions: 'Read full experiment doc|https://github.com/theontho/gui-for-cli/blob/main/docs/desktop-gui-experiments.md|primary; WGSExtract story|wgsextract.html'
footer_title: 'Experiment archive'
footer_text: 'Benchmark data lives in docs/ai; the product frontend list stays intentionally short.'
---

::: section
::: wrap
::: section-head
## What the benchmark pass taught

The results below summarize the decision-making docs. Exact run details, caveats, and raw benchmark paths are under `docs/ai/`.
:::

| Surface | Main result | Product decision |
| --- | --- | --- |
| `swiftui-macos` | Small native package, native Apple integration, and strong marker-based startup after launch-work deferral. | Product frontend. |
| `tauri-webui` | Self-contained WebUI package with less custom shell code than a bespoke WebView wrapper. | Product frontend. |
| WebView shell | Useful macOS-only control point and sometimes leaner than Tauri. | Benchmark/control, not product. |
| Electron | Runtime can be competitive, but package and memory are much heavier. | Fallback benchmark only. |
| Browser WebUI | Good preview path if a browser is already open; cold browser launch is costly. | Development/preview only. |
| Slint, Raygui, ImGui, Gio, Flutter | Some won narrow size, startup, or memory categories. | Keep as research until full parity. |
| TUI and terminal paths | Useful low-overhead automation surfaces. | Not desktop GUI frontends. |
:::
:::

::: section
::: wrap
## Experiment inventory

The repository keeps platform experiments isolated so the main product code does not become a pile of half-supported shells.

| Group | Examples |
| --- | --- |
| Apple | iOS SwiftUI, Swift AppKit, Objective-C AppKit |
| TypeScript | NodeGui/Qt, WebUI development server, TUI |
| Rust | Dioxus, GTK4/libadwaita, Slint, ImGui, Iced, egui, Xilem/Vello, GPUI, Raygui, Makepad |
| C/C++ | C Raygui, C++ ImGui, Qt 6/QML |
| Go | Gio, Fyne |
| Python | Textual, Tkinter, wxPython, Toga/BeeWare |
| Dart/Kotlin/.NET/Mojo/Windows | Flutter, Compose Desktop, Android Compose, Avalonia, Mojo core, Windows C#/WinUI |

{{ button: Open the full experiment document|https://github.com/theontho/gui-for-cli/blob/main/docs/desktop-gui-experiments.md|primary }}
:::
:::

::: section
::: wrap
## Result

The experiments made the product sharper, not broader. `swiftui-macos` gives the native Apple path. `tauri-webui` gives the portable packaged WebUI path. Everything else is either support code, development tooling, or research until it proves product-level parity.
:::
:::
