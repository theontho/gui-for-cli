# Desktop GUI Platform Popularity Research

> Research compiled May 2026. Popularity signals (stars, downloads, Stack Overflow tags) were spot-checked at time of writing; all figures are approximate and subject to change. Developer-count estimates are deliberately wide-range inferences from multiple proxy signals; treat them as order-of-magnitude guides, not audited headcounts. See [Confidence and Caveats](#6-confidence-and-caveats) before drawing hard conclusions.

## Executive Summary

gui-for-cli currently tracks roughly **33 distinct surfaces**: 4 stable README rows, 7 stable surfaces if the Web UI packagers are split into WKWebView/Tauri/Electron, and 29 experimental entries in the README.[^readme-stable][^readme-exp] These span nearly every major desktop language ecosystem: Apple native, TypeScript web/TUI, Rust, Dart/Flutter, C/C++, Go, Python, Mojo, .NET, Kotlin, and Windows/WinUI.[^devarch-exp]

The largest uncovered audiences are **Python Qt users** (PySide6/PyQt combined ~11.4M PyPI downloads/month, estimated 50K-200K active developers), **JavaFX/JVM desktop** (estimated 50K-200K), **legacy .NET desktop** (WPF/WinForms, hundreds of thousands of mostly maintenance developers), and **Wails** (34K GitHub stars, the direct Go analogue of Tauri). By product fit, the best additions are **PySide6/Qt for Python**, **Wails**, **Neutralinojs**, and optionally **C++ wxWidgets**.

Several large ecosystems are worth tracking but not implementing: WPF, WinForms, Swing, and .NET MAUI all have real user bases but are a poor fit for gui-for-cli's current architecture and native-platform strategy. CEF/CefSharp, Photino, and Sciter mostly duplicate existing webview-shell coverage; JUCE, FLTK, Kivy, Gooey, Eto.Forms, SWT, and Nana are lower-fit or niche options.

## 1. Status Model and Measurement Notes

The README and development-architecture doc define the canonical platform list.[^readme-stable][^readme-exp][^devarch-stable][^devarch-exp] Counts vary depending on whether packagers and helper/headless runtimes are split: the README has 4 stable rows and 29 experimental rows; splitting the Web UI packagers into WKWebView, Tauri, and Electron yields about 33 distinct tracked surfaces.

This report now uses **one unified platform table** instead of separate implemented/candidate/stable tables. The **gui-for-cli status** column describes how each platform currently exists in this repository:

| Status | Meaning |
|---|---|
| Stable | Stable product surface in the repo. |
| Stable packager | Stable desktop shell for the TypeScript Web UI. |
| Experimental | Windowed experimental platform surface exists. |
| Experimental headless/core | Runtime/core validation exists, but no complete windowed UI. |
| Candidate - high | Not implemented; strong product-fit candidate. |
| Candidate - medium | Not implemented; worth tracking or implementing after higher-priority gaps. |
| Track only | Large/important ecosystem but not recommended as an implementation target. |
| Not recommended | Low fit, duplicate coverage, dormant, proprietary, or wrong domain. |
| Watchlist | Interesting niche, but not enough evidence for implementation. |

**Registry-stat caveats:** npm, PyPI, NuGet, and crates.io/lib.rs download counts are download events, not unique developers. Rust crates.io counts are available through lib.rs monthly histograms and are now filled into the unified table.[^rust-cratesio-stats] Go has no public module download counter comparable to npm/PyPI; the best public proxies are GitHub stars, module-version counts from `proxy.golang.org`, and GitHub code-search import hits.[^go-module-stats] JVM GUI platforms also lack public download counts because Maven Central and the Gradle Plugin Portal expose no download stats; Stack Overflow tag volume and release cadence are the strongest public signals.[^jvm-download-stats]

GitHub release asset downloads were evaluated separately. The API exposes `assets[].download_count`, but most framework repos publish no release assets, and package-manager installs bypass GitHub Releases; release downloads are useful for end-user apps, not framework-library popularity.[^github-release-stats]

## 2. Unified Platform Table

| Platform | Ecosystem | gui-for-cli status | Repo path / implementation | GitHub stars / forks | Package / registry numbers | Notes | Est. active devs | Fit / recommendation |
|---|---|---|---|---|---|---|---:|---|
| SwiftUI macOS | Swift / Apple | Stable | `platform/apple/swiftui`, `platform/apple/shared` | SDK-bundled | n/a | Primary macOS app; benchmarked in macOS comparison.[^mac-bench] | 100K-500K desktop Apple subset | Keep as primary macOS surface. |
| Web UI | TypeScript / Web | Stable | `platform/typescript/web`, `platform/typescript/shared` | n/a | Node/Web ecosystem proxy | Shared implementation used by packagers. | Node/web ecosystem scale | Keep as behavioral reference for web shells. |
| TypeScript TUI | TypeScript / Terminal | Stable | `platform/typescript/tui`, `platform/typescript/shared` | n/a | Node ecosystem proxy | No distinct package metric. | Node ecosystem scale | Keep terminal-first product surface. |
| WKWebView shell | Swift / WebView | Stable packager | `platform/typescript/web/packagers/*` | SDK-bundled | n/a | System WKWebView; benchmarked at ~515 ms in macOS comparison.[^mac-bench] | Apple developer subset | Keep as lean macOS Web UI shell. |
| Tauri | Rust + WebView | Stable packager | `platform/typescript/web/packagers/*` | 106.7K stars / 3.6K forks[^tauri-gh] | `tauri` ~2.02M crates.io/month; `wry` ~2.06M; `tauri-cli` ~82K; `@tauri-apps/api` ~4.65M npm/month.[^tauri-npm][^tauri-cratesio] | Registry counts include both framework and webview-layer transitive use. | 30K-100K | Keep as primary cross-platform lightweight Web UI shell. |
| Electron | JS/TS + Chromium | Stable packager | `platform/typescript/web/packagers/*` | 121.3K stars / 17.2K forks[^electron-gh] | ~15.5M npm downloads/month[^electron-npm] | Largest desktop web stack; heaviest runtime footprint. | 100K-500K | Keep as broadest desktop web baseline. |
| iOS SwiftUI app | Swift / Apple | Experimental | `platform/apple/exp/ios-swiftui` | SDK-bundled | n/a | Mobile companion to SwiftUI surface. | Apple mobile ecosystem scale | Keep as mobile experiment. |
| Swift AppKit | Swift / AppKit | Experimental | `platform/apple/exp/swift-appkit` | SDK-bundled | n/a | AppKit native macOS baseline.[^mac-bench] | 100K-500K Apple desktop subset | Keep as native macOS baseline. |
| Objective-C AppKit | ObjC / AppKit | Experimental | `platform/apple/exp/objc-appkit` | SDK-bundled | n/a | Legacy native macOS baseline.[^mac-bench] | 100K-500K Apple desktop subset | Keep for baseline comparison. |
| NodeGui/Qt | TypeScript / Qt | Experimental | `platform/typescript/exp/nodegui` | 9.2K stars[^nodegui-gh] | ~4.9K npm downloads/month[^nodegui-npm] | Low current activity. | <1K | Useful Qt+TS comparison only. |
| Dioxus shell | Rust / WebView | Experimental | `exp-platform/rust/dioxus-shell` | 36.1K stars / 1.7K forks[^dioxus-gh] | `dioxus` ~158K crates.io/month; `dioxus-desktop` ~60K/month[^dioxus-cratesio] | Overlaps Tauri because both use WRY/TAO. | 5K-20K | Keep as Rust shell comparison. |
| GTK4/libadwaita | Rust / GTK | Experimental | `exp-platform/rust/gtk4` | gtk-rs stars understate GTK ecosystem | `gtk4` ~150K crates.io/month; 240 dependent crates[^gtk4-cratesio] | Rust-specific GTK use is a small slice of GTK overall. | 1K-5K Rust-specific; GTK overall larger | Keep for Linux-native GTK comparison. |
| Slint | Rust / Slint | Experimental | `exp-platform/rust/slint` | 22.6K stars[^slint-gh] | `slint` ~93K crates.io/month[^slint-cratesio] | 48 stable semver releases; release compiler asset downloads are low. | 3K-15K | Keep; strong embedded/desktop signal. |
| Rust ImGui | Rust / Dear ImGui | Experimental | `exp-platform/rust/imgui` | Upstream Dear ImGui 73.2K stars[^imgui-gh] | `imgui` crate ~11.4K/month[^imgui-cratesio] | Rust bindings are a subset of the broader ImGui ecosystem. | Rust subset of 200K-1M ImGui ecosystem | Keep for Rust immediate-mode baseline. |
| Iced | Rust / Iced | Experimental | `exp-platform/rust/iced` | 30.5K stars[^iced-gh] | `iced` ~122K crates.io/month[^iced-cratesio] | 23 releases, 13 breaking. | 3K-15K | Keep; major Rust retained/declarative GUI. |
| Rust egui / eframe | Rust / egui | Experimental | `exp-platform/rust/egui` | 29.1K stars[^egui-gh] | `egui` ~1.33M crates.io/month; `eframe` ~1.12M/month[^egui-cratesio] | 1,613 dependent crates; strongest Rust GUI download signal but CI/transitive inflated. | 5K-25K | Keep. |
| Rust Xilem/Vello | Rust / Linebender | Experimental headless/core | `exp-platform/rust/xilem-vello` | Xilem 5.3K stars[^xilem-gh] | `xilem` ~300 crates.io/month; `vello` ~36K/month[^vello-cratesio] | Research-stage; renderer has broader use than Xilem app framework. | <1K Xilem direct | Keep as research-stage renderer; not full UI yet. |
| Rust GPUI | Rust / GPUI | Experimental headless/core | `exp-platform/rust/gpui` | Zed proxy: 83K stars[^gpui-zed] | `gpui` ~19.6K crates.io/month[^gpui-cratesio] | Downloads/dependents are mostly Zed-internal. | <500 standalone | Keep as headless until dependency/build blockers clear. |
| Raygui (Rust) | Rust / raylib | Experimental | `exp-platform/rust/raygui` | raylib 33K stars[^raylib-gh] | `raylib` crate ~12K/month[^raylib-cratesio] | No separate `raygui` crate; raygui support comes through raylib bindings/features. | Rust subset of 5K-30K raygui/raylib users | Keep lightweight immediate-mode baseline. |
| Makepad | Rust / Makepad | Experimental | `exp-platform/rust/makepad` | 6.4K stars[^makepad-gh] | `makepad-widgets` ~328 crates.io/month[^makepad-cratesio] | Registry usage is low despite active repo. | <2K | Keep as niche GPU-first Rust comparison. |
| Flutter | Dart / Flutter | Experimental | `exp-platform/dart/flutter` | 176.3K stars / 30.4K forks[^flutter-gh] | pub.dev ecosystem; no specific package count in this table | Google claims 1M+ total Flutter developers; desktop subset is smaller. | 50K-200K desktop subset | Keep; major cross-platform/mobile ecosystem. |
| C Raygui | C / raygui | Experimental | `exp-platform/c/raygui` | raylib 33K stars[^raylib-gh] | n/a | raygui is a lightweight tool GUI add-on. | 5K-30K | Keep smallest C baseline; accessibility caveats. |
| C++ ImGui | C++ / Dear ImGui | Experimental | `exp-platform/cpp/imgui-cpp` | Dear ImGui 73.2K stars / 11.8K forks[^imgui-gh] | n/a | Strong game/tooling adoption. | 200K-1M | Keep; fastest measured UI-ready baseline. |
| Qt 6/QML | C++ / Qt | Experimental | `exp-platform/cpp/qt-qml` | GitHub mirrors understate Qt | No public central package download count | Qt/QML SO volume ~90K-120K; Qt Company has claimed 1.5M developers.[^qt-so][^qt-devcount] | 150K-500K | Keep; major enterprise/embedded GUI baseline. |
| Go Gio | Go / Gio | Experimental | `exp-platform/go/gio` | 2.2K GitHub mirror stars[^gio-gh] | No public Go download count | 14 tagged proxy versions; code-search `import "gioui.org/app"` ~1,320 files; GitHub stars undercount Sourcehut community.[^go-module-stats] | 500-3K | Keep niche Go renderer. |
| Go Fyne | Go / Fyne | Experimental | `exp-platform/go/fyne` | 28.3K stars / 1.5K forks[^fyne-gh] | No public Go download count | `fyne.io/fyne/v2` has 108+ proxy versions; code-search imports ~2,836 files.[^go-module-stats] | 5K-20K | Keep; dominant Go GUI framework. |
| Python shared runtime | Python | Experimental headless/core | `exp-platform/python/shared` | n/a | n/a | Shared core for Python renderers, not an independent GUI ecosystem metric.[^devarch-exp] | n/a | Keep as shared runtime. |
| Python Textual | Python / TUI | Experimental | `exp-platform/python/textual` | 35.9K stars[^textual-gh] | ~268M PyPI/month[^textual-pypi] | PyPI count is heavily transitive/CI-inflated. | 20K-100K app builders | Keep TUI experiment. |
| Python Tkinter | Python / Tk | Experimental | `exp-platform/python/tkinter` | stdlib | n/a | `tkinter` SO tag ~52,989; JetBrains Python survey ~17% usage.[^tkinter-so][^jb-survey] | 500K-3M | Keep zero-dependency Python GUI baseline. |
| Python wxPython | Python / wxWidgets | Experimental | `exp-platform/python/wx` | n/a | ~164.6K PyPI/month[^wx-pypi] | Mature native-widget Python GUI. | 10K-50K | Keep native-widget Python baseline. |
| Python Toga/BeeWare | Python / Toga | Experimental | `exp-platform/python/toga` | 5.4K stars[^toga-gh] | ~16.5K PyPI/month[^toga-pypi] | BeeWare/native-mobile comparison. | 1K-5K | Keep. |
| Mojo | Mojo | Experimental headless/core | `exp-platform/mojo` | n/a | n/a | No broad GUI ecosystem metric; validates runtime/core contract.[^devarch-exp] | <5K | Keep experimental language/runtime validation. |
| Avalonia | C# / .NET | Experimental | `exp-platform/dotnet/avalonia` | 30.8K stars[^avalonia-gh] | Avalonia.Desktop ~9.7M NuGet downloads; 1,400+ dependents[^avalonia-nuget] | Main cross-platform .NET experiment. | 15K-60K | Keep. |
| Compose Multiplatform Desktop | Kotlin / JVM | Experimental | `exp-platform/kotlin/compose/desktopApp` | 19.1K stars[^compose-gh] | Maven/Gradle downloads not public | SO `compose-multiplatform` ~380, Android Compose tag ~14.6K; Sonatype "Used in" is not app adoption.[^jvm-download-stats] | 5K-30K desktop | Keep; update dependencies when practical. |
| Jetpack Compose Android | Kotlin / Android | Experimental | `exp-platform/kotlin/compose/androidApp` | Android/JetBrains ecosystem | Maven/Gradle downloads not public | Android Compose ecosystem much larger than desktop; Android Compose SO tag ~14.6K.[^jvm-download-stats] | Android Compose ecosystem scale | Keep mobile comparison. |
| Windows C#/WinUI | C# / WinUI 3 | Experimental | `exp-platform/windows/dotnet` | 7.6K `microsoft-ui-xaml` stars[^winui-gh] | Windows App SDK / NuGet ecosystem | Native Windows direction selected by repo docs. | 20K-100K | Keep as native Windows direction. |
| PySide6 / PyQt | Python / Qt | Candidate - high | Not implemented | n/a | PySide6 ~2.32M PyPI/month; PyQt6 ~5.92M; PyQt5 ~3.17M[^pyside6-pypi][^pyqt6-pypi][^pyqt5-pypi] | PyQt ~12% in JetBrains survey; prefer PySide6 licensing.[^pyqt-so][^jb-survey] | 50K-200K | Highest-priority missing Python GUI. |
| Wails | Go + WebView | Candidate - high | Not implemented | 34.1K stars / 1.7K forks[^wails-gh] | No public Go download count | v2 module has 130+ proxy versions; code-search imports ~2,668 files.[^go-module-stats] | 5K-20K | Strong Go webview-shell candidate; Node backend integration required. |
| Neutralinojs | JS/TS + WebView | Candidate - high | Not implemented | 8.5K stars[^neutralino-gh] | `@neutralinojs/neu` ~16K npm/month[^neutralino-npm] | Lightweight webview packager candidate. | 2K-10K | High-value packager candidate. |
| JavaFX / OpenJFX | Java / JVM | Candidate - medium | Not implemented | 3.2K stars / 576 forks[^javafx-gh] | Maven downloads not public | ~39K `javafx` SO questions; 6-month JDK-aligned cadence, LTS branches 17/21/25.[^javafx-so][^jvm-download-stats] | 50K-200K | Largest missing modern JVM desktop toolkit. |
| Uno Platform | C# / .NET | Candidate - medium | Not implemented | ~10K stars[^uno-gh] | Uno.WinUI 10M+ NuGet downloads; 130M+ ecosystem claim[^uno-nuget] | WinUI-everywhere alternative to Avalonia. | 5K-30K | Monitor. |
| React Native macOS/Windows | JS/TS / React Native | Candidate - medium | Not implemented; prior benchmark branch documented | React Native Windows ~16K stars[^rnw-gh] | npm ecosystem, desktop-specific numbers not isolated | No Linux; bridge complexity. | 5K-30K desktop-specific | Monitor. |
| C++ wxWidgets | C++ / wxWidgets | Candidate - medium | Not implemented; Python wxPython exists | ~6K-7K stars[^wx-gh] | n/a | ~19K `wxwidgets` SO questions.[^wx-so] | 10K-50K | Good C++ native-controls gap, but lower than PySide6/Wails. |
| Dear PyGui | Python / Dear ImGui | Candidate - medium | Not implemented; C++/Rust ImGui exist | ~13.5K-15.4K stars[^dearpygui-gh] | ~147.7K PyPI/month[^dearpygui-pypi] | Python immediate-mode parity surface. | 5K-20K | Optional. |
| Swing | Java / JDK stdlib | Track only | Not implemented | JDK stdlib | n/a | `swing` SO volume ~81K; no Maven artifact; bundled in JDK `java.desktop`.[^swing-so][^jvm-download-stats] | 100K-500K legacy | Track for ecosystem completeness, not implementation. |
| WPF | C# / .NET | Track only | Not implemented | Microsoft repo active[^wpf-gh] | SDK-bundled | High SO activity; Windows plan rejects it for primary UI.[^windows-native-decision] | 100K-500K legacy | Track only. |
| WinForms | C# / .NET | Track only | Not implemented | Microsoft repo active[^winforms-gh] | SDK-bundled | Massive Windows LOB legacy base. | 100K-500K+ legacy | Track only; wrong model for gui-for-cli. |
| .NET MAUI | C# / .NET | Not recommended | Not implemented | ~23.2K stars[^maui-gh] | Microsoft.Maui.Controls ~24.4M NuGet downloads[^maui-nuget] | Abstraction over WinUI/Mac Catalyst; no Linux. | 30K-100K | Not recommended. |
| SWT | Java / Eclipse | Not recommended | Not implemented | 194 stars; Eclipse infra undercounts[^swt-gh] | Maven downloads not public | ~6.1K `swt` SO questions.[^swt-so][^jvm-download-stats] | 5K-20K | Eclipse-centric; no advantage over JavaFX. |
| Kivy | Python | Not recommended | Not implemented | ~18K stars[^kivy-gh] | ~243K PyPI/month[^kivy-pypi] | ~13.8K SO questions; touch/mobile-first.[^kivy-so] | 10K-50K | Poor desktop CLI-wrapper fit. |
| CEF/CefSharp | C++ / C# | Not recommended | Not implemented | CefSharp ~10.2K stars[^cefsharp-gh] | n/a | CEF claims 100M+ installed instances; duplicates Electron's Chromium niche. | 10K-50K integrators | Not recommended. |
| Photino | C# / .NET | Not recommended | Not implemented | Photino.NET 1.3K stars[^photino-gh] | Photino.Blazor ~102K NuGet downloads[^photino-nuget] | Small community; OS-webview shell duplicate. | <5K | Not recommended. |
| Gooey | Python / wxPython | Not recommended | Not implemented | ~22K stars[^gooey-gh] | ~7.2K PyPI/month[^gooey-pypi] | Useful prior art, not a platform target. | 5K-20K historical | Not recommended. |
| Eto.Forms | C# / .NET | Not recommended | Not implemented | n/a | Eto.Platform.Gtk ~423K downloads; WPF ~416K; 51 dependents[^eto-nuget] | Smaller and less aligned than Avalonia/Uno. | 1K-5K | Not recommended. |
| FLTK | C++ | Not recommended | Not implemented | ~2.2K stars[^fltk-gh] | n/a | Duplicates Raygui/ImGui lightweight niche. | 2K-10K | Not recommended. |
| JUCE | C++ | Not recommended | Not implemented | ~8.4K stars[^juce-gh] | n/a | Audio-domain-specific; GPL/commercial. | 5K-30K audio developers | Not recommended. |
| Sciter | C++ / custom web | Not recommended | Not implemented | n/a | n/a | Proprietary/custom engine.[^sciter-note] | <5K | Not recommended. |
| Nana | C++ | Not recommended | Not implemented | ~2.5K stars[^nana-gh] | n/a | Dormant. | <2K | Not recommended. |
| RmlUi | C++ | Watchlist | Not implemented | ~4K stars[^rmlui-gh] | n/a | Niche C++ HTML/CSS renderer. | <2K | Watchlist only. |

## 3. Webview-Shell Landscape

gui-for-cli already covers the core webview-shell families:

| Shell | Technology | Status | Notes |
|---|---|---|---|
| WKWebView shell | Swift + WKWebView | Stable | macOS-only, lean native shell. |
| Tauri | Rust + WRY/TAO | Stable | Cross-platform OS-webview shell. |
| Electron | Node.js + bundled Chromium | Stable | Largest ecosystem, heaviest runtime. |
| Dioxus shell | Rust + WRY/TAO | Experimental | Overlaps Tauri, same webview layer. |

Candidate webview shells mostly fill language or footprint niches:

| Candidate | Technology | Assessment |
|---|---|---|
| Wails | Go + OS webview | Best missing webview-shell candidate; direct Go/Tauri analogue. |
| Neutralinojs | C++ binary + JS IPC | Tiny OS-webview packager; high value for packager taxonomy completeness. |
| Photino | .NET + OS webview | Small .NET community; duplicates Tauri category. |
| CEF/CefSharp | Bundled Chromium | Duplicates Electron at similar or higher complexity. |
| Sciter | Proprietary custom HTML/CSS engine | Nonstandard and licensing-constrained. |

The key integration constraint is that gui-for-cli's Web UI depends on a TypeScript/Node.js backend for bundle loading, process execution, config storage, and data-source evaluation. Wails or Neutralino would need to either bundle Node like the existing shells or rewrite backend responsibilities in Go/C++.[^webview-shell-research]

## 4. Prioritised Recommendations

### Tier 1 - High priority additions

| Platform | Rationale |
|---|---|
| **PySide6 (Qt for Python)** | Largest uncovered Python GUI audience; strong download/survey signals; Python runtime already established. Prefer PySide6 over PyQt for LGPL licensing. |
| **Wails** | Largest missing Go webview-shell framework; complements existing Go Gio/Fyne with a Tauri-like webview shell. |
| **Neutralinojs** | Tiny OS-webview packager; natural addition next to WKWebView shell, Tauri, and Electron. |

### Tier 2 - Medium priority / worth tracking

| Platform | Rationale |
|---|---|
| **JavaFX** | Largest missing modern JVM desktop toolkit; significant SO depth and active OpenJFX releases. |
| **Uno Platform** | WinUI-everywhere alternative to Avalonia for .NET cross-platform experiments. |
| **React Native macOS/Windows** | Existing docs mention a benchmark branch; native-ish JS/TS path, but bridge complexity and no Linux. |
| **C++ wxWidgets** | Native controls from C++; complements Qt/ImGui and parallels existing wxPython. |
| **Dear PyGui** | Python immediate-mode GUI parity with existing ImGui experiments. |

### Tier 3 - Track for completeness only

Swing, WPF, and WinForms are large enough that ecosystem maps should mention them, but they should not become implementation targets. Swing is legacy JVM UI; WPF and WinForms are Windows-only legacy .NET UI stacks and the Windows implementation plan already chose WinUI 3 instead.[^windows-native-decision]

### Tier 4 - Rejected / not recommended

| Platform | Reason |
|---|---|
| .NET MAUI | Abstraction over WinUI and Mac Catalyst, no Linux; explicitly rejected in Windows plan. |
| SWT | Eclipse-centric and smaller than JavaFX. |
| CEF/CefSharp | Duplicates Electron's full-Chromium niche. |
| Photino | Small community; duplicates OS-webview shell category. |
| Sciter | Proprietary/nonstandard custom engine. |
| Gooey | Useful prior art, but low maintenance and wxPython-based. |
| JUCE | Audio-domain framework and GPL/commercial. |
| Kivy | Touch/mobile-first, custom rendering, weaker desktop fit. |
| FLTK | Lightweight but overlaps Raygui/ImGui minimal-GUI niche. |
| Eto.Forms | Smaller than Avalonia/Uno and less aligned with current .NET direction. |
| Nana | Dormant. |
| RmlUi | Niche watchlist only. |

## 5. Detailed Deprioritisation Notes

### WPF and WinForms

WPF and WinForms represent huge legacy Windows developer populations, but gui-for-cli's Windows design already chose WinUI 3 for Fluent controls, native UI Automation, DPI behavior, and Windows process integration.[^windows-native-decision] WPF lacks native Mica/Acrylic and has weaker Windows 11 fit; WinForms is GDI+/User32-era UI with no natural XAML/DataTemplate model.

### .NET MAUI

.NET MAUI is popular and Microsoft-backed, but it is not a good desktop-first fit here. Windows uses WinUI 3 through an abstraction layer, macOS uses Mac Catalyst instead of AppKit/SwiftUI, and Linux desktop is absent.[^windows-native-decision]

### Electron vs CEF

Electron already covers the full-Chromium desktop shell path. CEF/CefSharp adds low-level embedding power but duplicates Electron's footprint and runtime model without giving gui-for-cli an obvious capability it lacks.

### Gooey as prior art

Gooey is the closest conceptual predecessor: it wraps Python argparse CLIs in a wxPython GUI. It is worth mentioning in competitive/prior-art docs, but not as a platform target because gui-for-cli already has wxPython coverage and uses a richer bundle/manifest model rather than instrumenting argparse.

## 6. Confidence and Caveats

### 6.1 Stars and downloads are proxies

GitHub stars correlate with developer interest, not active usage. Package downloads are inflated by CI, mirrors, transitive dependencies, and automation. Textual's ~268M PyPI downloads/month is the clearest example: the actual active application-builder population is likely orders of magnitude smaller.[^textual-pypi]

### 6.2 Developer-count estimates are wide bands

All estimated developer counts are triangulated from stars, download counts, Stack Overflow tag volume, surveys, vendor claims, and ecosystem context. They are not audited figures. Interpret bands as:

| Range | Meaning |
|---|---|
| <5K | Niche community |
| 5K-50K | Meaningful ecosystem |
| 50K-500K | Major ecosystem |
| >500K | Dominant or legacy-scale ecosystem |

### 6.3 Fit matters more than popularity

WinForms, WPF, Swing, and .NET MAUI are more popular than many implemented experiments, but they fit gui-for-cli less well than smaller frameworks like Wails or PySide6. Fit was assessed by subprocess/terminal integration, data-driven UI support, cross-platform reach, maintenance cost, and ecosystem health.

### 6.4 Registry-specific caveats

**Rust / Cargo:** crates.io/lib.rs monthly downloads are now included for Rust GUI crates. These count every crate download event, including CI and transitive dependencies. `egui` and `eframe` are especially inflated because they are embedded by many downstream game/tooling crates; `wry` is mostly a transitive dependency of Tauri/Dioxus rather than direct adoption.[^rust-cratesio-stats]

**Go:** Go has no public module download counter. `proxy.golang.org` exposes module version lists but not access metrics, and `pkg.go.dev` "Imported by" counts are JavaScript-rendered with no public API. The Go rows therefore use GitHub stars, release cadence, module-version counts, and GitHub code-search import hits as directional proxies.[^go-module-stats]

**JVM / Maven / Gradle:** Maven Central stopped exposing public download counts, and the Gradle Plugin Portal does not expose usage statistics. Sonatype's "Used in N components" counts only Maven-published library dependencies and undercounts end-user app frameworks. For JVM GUI frameworks, Stack Overflow tag volume and release cadence are the most useful public signals.[^jvm-download-stats]

### 6.5 GitHub release asset download counts

GitHub release asset `download_count` was evaluated and excluded as a primary metric. The REST API exposes `download_count` for uploaded release assets, but most framework repos publish source-only releases with `assets: []`; package-manager installs go through npm, crates.io, Go modules, NuGet, Maven, or PyPI instead. Even where prebuilt CLI assets exist, counts are tiny compared with package-registry installs. Release asset counts are meaningful for end-user desktop apps distributed through GitHub Releases, not framework-library popularity.[^github-release-stats]

### 6.6 Known uncertainties

- Several star counts are approximate because some projects are hosted outside GitHub or have misleading mirrors (Qt, Gio, SWT).
- Some vendor claims, such as Qt's 1.5M developers or CEF's 100M+ installed instances, are treated as marketing/adoption signals, not audited developer counts.
- Compose Multiplatform in this repo is pinned to Kotlin 1.9.24 / Compose 1.6.11 while upstream has moved significantly; version drift should be tracked.[^compose-version-note]
- GPUI and Xilem/Vello are headless/core only and should not be compared directly with full windowed apps.[^gpui-notes][^xilem-notes]

## Footnotes

[^readme-stable]: `README.md:10-17` — stable surfaces table listing SwiftUI macOS app, Web UI, TypeScript TUI, and Web UI packagers.

[^readme-exp]: `README.md:23-65` — platform split count table and full experimental surface list.

[^devarch-stable]: `docs/ai/development-architecture.md:4-21` — stable platform code path table.

[^devarch-exp]: `docs/ai/development-architecture.md:23-57` — experimental platform code paths including experimental surfaces.

[^windows-native-decision]: `docs/ai/platforms/windows-native.md:1-39` — Windows implementation decision: WinUI 3 adopted; WPF, .NET MAUI, Tauri/WebView2, Electron, and React Native Windows rejected as primary Windows target.

[^benchmark-findings]: `docs/ai/benchmark-findings.md:6-23` — macOS benchmark comparison table with package size, startup time, and RSS for measured surfaces.

[^mac-bench]: `docs/ai/platforms/new-mac-benchmark.md:11-30` — macOS benchmark run including SwiftUI, AppKit, WKWebView, Tauri, Electron, React Native macOS, and Go Gio.

[^full-bench-2026-05-14]: `docs/ai/full-platform-benchmark-2026-05-14.md:27-30` — full platform benchmark `ui_ready_ms` results.

[^gio-bench]: `docs/ai/platforms/go-gio.md:1-15` — Go Gio benchmark notes and current macOS blocker.

[^gpui-notes]: `docs/ai/platforms/rust-gpui.md:1-25` — GPUI headless/core notes and Metal shader build blocker.

[^xilem-notes]: `docs/ai/development-architecture.md:37` — Xilem/Vello headless/core status.

[^compose-version-note]: Research finding: `exp-platform/kotlin/compose/build.gradle.kts` pins Kotlin 1.9.24 and Compose 1.6.11; upstream Compose Multiplatform had reached 1.11.0 in the May 2026 research snapshot.

[^webview-shell-research]: Research finding from webview-shell subagent: Wails and Neutralino use OS webviews; gui-for-cli would need to embed Node like existing shells or rewrite the backend in Go/C++.

[^rust-cratesio-stats]: Rust crate usage research used lib.rs crate pages as a crates.io download proxy because direct crates.io API requests require a proper user agent. Figures are monthly download histograms from lib.rs for May 2026; downloads are events, not unique users.

[^go-module-stats]: Go usage research: `proxy.golang.org` exposes module version lists such as `https://proxy.golang.org/fyne.io/fyne/v2/@v/list`, `https://proxy.golang.org/github.com/wailsapp/wails/v2/@v/list`, and `https://proxy.golang.org/gioui.org/@v/list`, but no public per-module download counts. Code-search import counts were directional only.

[^jvm-download-stats]: JVM usage research: Maven Central and the Gradle Plugin Portal do not expose public download counts. Stack Overflow tag counts, release cadence, Maven coordinates, and Sonatype "Used in" dependency-graph counts were used as public proxies.

[^github-release-stats]: GitHub REST API release docs: https://docs.github.com/en/rest/releases/releases and release asset docs: https://docs.github.com/en/rest/releases/assets. `assets[].download_count` counts uploaded assets only, not source archives or package-manager installs.

[^jb-survey]: JetBrains Python Developer Survey, current survey landing page: https://www.jetbrains.com/research/python-developers-survey/.

[^electron-gh]: GitHub: https://github.com/electron/electron — 121,297 stars, 17,189 forks in the May 2026 research snapshot.

[^electron-npm]: npm package `electron`; ~15,508,324 downloads/month in the May 2026 research snapshot.

[^tauri-gh]: GitHub: https://github.com/tauri-apps/tauri — 106,713 stars, 3,607 forks.

[^tauri-npm]: npm package `@tauri-apps/api`; ~4,653,662 downloads/month.

[^tauri-cratesio]: lib.rs crate pages `https://lib.rs/crates/tauri`, `https://lib.rs/crates/tauri-cli`, and `https://lib.rs/crates/wry`; May 2026 monthly download snapshot: `tauri` ~2.02M, `wry` ~2.06M, `tauri-cli` ~82K.

[^flutter-gh]: GitHub: https://github.com/flutter/flutter — 176,333 stars, 30,374 forks.

[^imgui-gh]: GitHub: https://github.com/ocornut/imgui — 73,244 stars, 11,767 forks.

[^dioxus-gh]: GitHub: https://github.com/DioxusLabs/dioxus — 36,052 stars, 1,656 forks.

[^dioxus-cratesio]: lib.rs crate pages `https://lib.rs/crates/dioxus` and `https://lib.rs/crates/dioxus-desktop`; May 2026 monthly download snapshot: `dioxus` ~158K, `dioxus-desktop` ~60K.

[^iced-gh]: GitHub: https://github.com/iced-rs/iced — 30,508 stars.

[^iced-cratesio]: lib.rs crate page `https://lib.rs/crates/iced`; May 2026 monthly download snapshot: `iced` ~122K.

[^egui-gh]: GitHub: https://github.com/emilk/egui — 29,072 stars.

[^egui-cratesio]: lib.rs crate pages `https://lib.rs/crates/egui` and `https://lib.rs/crates/eframe`; May 2026 monthly download snapshot: `egui` ~1.33M, `eframe` ~1.12M, with 1,613 dependent crates.

[^slint-gh]: GitHub: https://github.com/slint-ui/slint — 22,608 stars.

[^slint-cratesio]: lib.rs crate page `https://lib.rs/crates/slint`; May 2026 monthly download snapshot: `slint` ~93K, with 48 semver-stable releases.

[^makepad-gh]: GitHub: https://github.com/makepad/makepad — 6,415 stars.

[^makepad-cratesio]: lib.rs crate page `https://lib.rs/crates/makepad-widgets`; May 2026 monthly download snapshot: `makepad-widgets` ~328.

[^xilem-gh]: GitHub: https://github.com/linebender/xilem — 5,315 stars.

[^vello-cratesio]: lib.rs crate pages `https://lib.rs/crates/xilem` and `https://lib.rs/crates/vello`; May 2026 monthly download snapshot: `xilem` ~300, `vello` ~36K.

[^gpui-zed]: GitHub: https://github.com/zed-industries/zed — 82,982 stars; used as a proxy for GPUI visibility, not GPUI external adoption.

[^gpui-cratesio]: lib.rs crate page `https://lib.rs/crates/gpui`; May 2026 monthly download snapshot: `gpui` ~19.6K, with most dependent crates likely Zed-internal.

[^raylib-gh]: GitHub: https://github.com/raysan5/raylib — 32,951 stars.

[^raylib-cratesio]: lib.rs crate page `https://lib.rs/crates/raylib`; May 2026 monthly download snapshot: `raylib` ~12K. No separate `raygui` crate exists on crates.io/lib.rs; raygui support is bundled via raylib bindings/features.

[^gtk4-cratesio]: lib.rs crate page `https://lib.rs/crates/gtk4`; May 2026 monthly download snapshot: `gtk4` ~150K, with 240 dependent crates.

[^imgui-cratesio]: lib.rs crate page `https://lib.rs/crates/imgui`; May 2026 monthly download snapshot: `imgui` ~11.4K.

[^fyne-gh]: GitHub: https://github.com/fyne-io/fyne — 28,265 stars.

[^avalonia-gh]: GitHub: https://github.com/AvaloniaUI/Avalonia — 30,804 stars.

[^avalonia-nuget]: NuGet package data for Avalonia.Desktop and Avalonia dependents; ~9.7M Avalonia.Desktop downloads and 1,400+ dependent packages in the May 2026 research snapshot.

[^winui-gh]: GitHub: https://github.com/microsoft/microsoft-ui-xaml — 7,581 stars.

[^compose-gh]: GitHub: https://github.com/JetBrains/compose-multiplatform — 19,060 stars.

[^nodegui-gh]: GitHub: https://github.com/nodegui/nodegui — 9,209 stars.

[^nodegui-npm]: npm package `@nodegui/nodegui`; ~4,855 downloads/month.

[^textual-gh]: GitHub: https://github.com/Textualize/textual — 35,920 stars.

[^textual-pypi]: PyPI package `textual`; ~268M downloads/month in the research snapshot, heavily inflated by transitive CI dependencies.

[^tkinter-so]: Stack Overflow `tkinter` tag; ~52,989 questions.

[^toga-gh]: GitHub: https://github.com/beeware/toga — 5,357 stars.

[^toga-pypi]: PyPI package `toga`; ~16,511 downloads/month.

[^wx-pypi]: PyPI package `wxPython`; ~164,554 downloads/month.

[^qt-so]: Stack Overflow `qt` and `qml` tag volume, roughly 90K-120K questions in the research snapshot.

[^qt-devcount]: Qt Company marketing claim of roughly 1.5M developers; treated as a non-audited upper-bound adoption signal.

[^gio-gh]: GitHub mirror https://github.com/gioui/gio; canonical repository hosted at Sourcehut.

[^pyside6-pypi]: PyPI package `PySide6`; ~2.32M downloads/month.

[^pyqt6-pypi]: PyPI package `PyQt6`; ~5.92M downloads/month.

[^pyqt5-pypi]: PyPI package `PyQt5`; ~3.17M downloads/month.

[^pyqt-so]: Stack Overflow: `pyqt` 17,242; `pyqt5` 14,812; `pyside6` 1,140; `pyqt6` 1,036 questions.

[^javafx-gh]: GitHub: https://github.com/openjdk/jfx — 3,235 stars, 576 forks.

[^javafx-so]: Stack Overflow `javafx` tag; ~39,031 questions.

[^swing-so]: Stack Overflow `swing` / `java-swing` tag volume; ~81,399 questions.

[^wails-gh]: GitHub: https://github.com/wailsapp/wails — 34,121 stars, 1,686 forks.

[^neutralino-gh]: GitHub: https://github.com/neutralinojs/neutralinojs — 8,504 stars.

[^neutralino-npm]: npm package `@neutralinojs/neu`; ~15,956 downloads/month.

[^maui-gh]: GitHub: https://github.com/dotnet/maui — ~23,200 stars.

[^maui-nuget]: NuGet packages `Microsoft.Maui.Controls` and `Microsoft.Maui.Graphics`; ~24.4M and ~40.1M downloads respectively.

[^uno-gh]: GitHub: https://github.com/unoplatform/uno — ~10,000 stars.

[^uno-nuget]: NuGet package `Uno.WinUI`; 10M+ downloads; Uno ecosystem claim of 130M+ downloads.

[^wpf-gh]: GitHub: https://github.com/dotnet/wpf.

[^winforms-gh]: GitHub: https://github.com/dotnet/winforms.

[^swt-gh]: GitHub: https://github.com/eclipse-platform/eclipse.platform.swt — 194 stars, noting Eclipse infra history.

[^swt-so]: Stack Overflow `swt` tag; ~6,121 questions.

[^rnw-gh]: GitHub: https://github.com/microsoft/react-native-windows — ~16,000 stars.

[^wx-gh]: GitHub: https://github.com/wxWidgets/wxWidgets — ~6,000-7,000 stars.

[^wx-so]: Stack Overflow `wxwidgets` tag; ~19,000 questions.

[^dearpygui-gh]: GitHub: https://github.com/hoffstadt/DearPyGui — ~13,500-15,400 stars.

[^dearpygui-pypi]: PyPI package `dearpygui`; ~147,700 downloads/month.

[^kivy-gh]: GitHub: https://github.com/kivy/kivy — ~18,000 stars.

[^kivy-pypi]: PyPI package `kivy`; ~243,000 downloads/month.

[^kivy-so]: Stack Overflow `kivy` tag; ~13,774 questions.

[^gooey-gh]: GitHub: https://github.com/chriskiehl/Gooey — ~22,000 stars.

[^gooey-pypi]: PyPI package `gooey`; ~7,200 downloads/month.

[^cefsharp-gh]: GitHub: https://github.com/cefsharp/CefSharp — ~10,221 stars.

[^photino-gh]: GitHub: https://github.com/tryphotino/photino.NET and https://github.com/tryphotino/photino.Native — 1,261 and 177 stars respectively.

[^photino-nuget]: NuGet package `Photino.Blazor`; ~102K downloads.

[^sciter-note]: Sciter project website: https://sciter.com; proprietary/custom HTML/CSS/JS-like engine.

[^fltk-gh]: GitHub: https://github.com/fltk/fltk — ~2,200 stars.

[^juce-gh]: GitHub: https://github.com/juce-framework/JUCE — ~8,400 stars.

[^eto-nuget]: NuGet packages `Eto.Platform.Gtk` and `Eto.Platform.Wpf`; ~423K and ~416K downloads respectively, 51 dependent packages for Eto.Forms.

[^nana-gh]: GitHub: https://github.com/cnjinhao/nana — ~2,500 stars; dormant.

[^rmlui-gh]: GitHub: https://github.com/mikke89/RmlUi — ~4,000 stars.
