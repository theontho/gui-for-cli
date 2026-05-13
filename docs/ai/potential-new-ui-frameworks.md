# Potential New Desktop UI Frameworks

The repository already has experiments for SwiftUI, Web/Electron/Tauri, NodeGUI, Flutter, Gio, Slint, Dioxus desktop, raygui, ImGui, and WinUI. Android and Compose Multiplatform Desktop are out of scope for this list.

| Platform | Why it's interesting |
| --- | --- |
| egui / eframe | Probably the best next pick if ImGui felt interesting. Immediate-mode Rust UI, much more ergonomic than raw ImGui, good desktop packaging, and fast iteration. |
| iced | Rust, Elm-style retained UI on top of `wgpu`. Good contrast with ImGui/egui and Slint. |
| Qt 6 / QML | Mature cross-platform desktop baseline. Strong widgets, model/view, accessibility, theming, and packaging; useful as a serious native app comparison. |
| Avalonia UI | Cross-platform .NET/XAML. Since the repo already has WinUI, Avalonia answers what the Windows stack looks like when it also runs on macOS/Linux. |
| GTK4 / libadwaita | Best Linux-native experiment. Less exciting for macOS/Windows, but useful if Linux desktop quality matters. |
| Fyne | Go retained-mode UI; a good comparison against Gio's lower-level immediate-style model. |
| Makepad | Very experimental Rust GPU UI toolkit. Interesting in the same not-boring-webview category as ImGui and raygui. |

Recommended first wave: egui, iced, and Avalonia. If the goal is another "this feels different" experiment like ImGui, start with egui/eframe.
