# GUI toolkit PR results and conclusions

This note consolidates the GUI/toolkit experiments that landed in GitHub PRs or are still open as prototype PRs. It focuses on what each architecture buys us, why its package/runtime size looks the way it does, and which paths look worth continuing.

## Scope and caveats

- Merged PRs are treated as baseline results. Open PRs are useful prototype data, but their branches may be dirty or incomplete.
- Startup metrics are not perfectly identical across toolkits. Window-ready, WebUI-rendered, terminal one-shot, and Slint internal UI-ready measure different readiness points.
- Size has two meanings: self-contained user payload and app-specific code/assets. Native frameworks often shift payload into OS or runtime components, while Electron/WebView/Node paths often bundle more runtime with the app.
- Windows measurements were taken on Windows benchmark hosts documented in `aidocs/windows-benchmark.md`; macOS measurements are from `aidocs/macos-perf-testing.md`.

## PR inventory

| PR | State | Surface | Main result |
| ---: | --- | --- | --- |
| [#14](https://github.com/theontho/gui-for-cli/pull/14) | Merged | Native Windows C# / WinUI 3 | Full native Windows app path with manifest rendering, setup/action services, process handling, and Windows tests. |
| [#16](https://github.com/theontho/gui-for-cli/pull/16) | Merged | TypeScript TUI | Terminal-first UI sharing the WebUI model layer; best low-overhead non-desktop baseline. |
| [#18](https://github.com/theontho/gui-for-cli/pull/18) | Merged | Windows native/WebUI benchmark packaging | Added Windows benchmark docs, bootstrap packaging, and WebUI package numbers. |
| [#19](https://github.com/theontho/gui-for-cli/pull/19) | Merged | macOS WKWebView, Tauri, Electron/WebUI release options | Added macOS desktop shell comparisons and release tooling. |
| [#20](https://github.com/theontho/gui-for-cli/pull/20) | Merged | Windows Tauri and TUI results | Added Windows Tauri release benchmark and TUI runtime measurements. |
| [#21](https://github.com/theontho/gui-for-cli/pull/21) | Merged | Windows Electron results | Added measured Windows Electron package startup, memory, and size. |
| [#25](https://github.com/theontho/gui-for-cli/pull/25) | Merged | Tauri with already-open Edge/WebView2 spot-check | Showed that already-open Edge did not materially reduce the Tauri app process-set memory. |
| [#28](https://github.com/theontho/gui-for-cli/pull/28) | Open | Windows C# ReadyToRun / NativeAOT | Shows NativeAOT as the fastest and smallest optimized C# publish path in the follow-up run. |
| [#23](https://github.com/theontho/gui-for-cli/pull/23) | Open | Flutter desktop | Very strong Windows package/startup/memory prototype, but not full parity yet. |
| [#24](https://github.com/theontho/gui-for-cli/pull/24) | Open | React Native | Windows-origin prototype now also builds on macOS via `react-native-macos`; visual readiness still needs measurement. |
| [#27](https://github.com/theontho/gui-for-cli/pull/27) | Open | Go Gio | Small Go/Gio native-rendered prototype now builds and emits first-frame startup markers on macOS. |
| [#29](https://github.com/theontho/gui-for-cli/pull/29) | Open | Slint Rust | Extremely small native renderer prototype; follow-up work adds setup/action/terminal shell behavior, but the benchmark is still not full external window-ready. |
| [#30](https://github.com/theontho/gui-for-cli/pull/30) | Open | Dioxus Native WebUI shell | Rust shell around the WebUI/Node/WebView2 architecture; smaller package than Tauri/Electron but still WebView2-heavy. |
| [#31](https://github.com/theontho/gui-for-cli/pull/31) | Open | NodeGui / Qt | Good single-process runtime behavior, but the current Qt/Qode dependency payload is very large. |

## Top-line measurements

| Surface | Package/runtime size | Startup/readiness | Practical memory | Process/architecture shape |
| --- | ---: | ---: | ---: | --- |
| macOS SwiftUI | 9.2 MB app | 852.8 ms improved first-window marker; 1.83 s current visual start-to-rendered | 67-80 MB physical footprint | Native SwiftUI over Apple system frameworks. |
| macOS WKWebView + bundled Node | 109 MB `.app` | 453-718 ms rendered | 171 MB dirty footprint | Custom native shell + system WebKit + bundled Node backend. |
| macOS Tauri WebUI | 117.7 MB `.app` | 727 ms rendered | 152 MB dirty footprint | Tauri shell + WebView + bundled Node/WebUI. |
| macOS Electron WebUI | 270 MB `.app` | 495-667 ms rendered | 542 MB aggregate RSS | Electron bundles Chromium, Node, renderer/helpers, and backend. |
| Windows C# clean Release | 213.93 MB self-contained; 0.62 MB app-only payload | 420.1 ms median follow-up run | 154.7 MB working set / 69.7 MB private | Native WinUI 3 app with .NET/Windows App SDK payload. |
| Windows C# ReadyToRun | 258.28 MB self-contained | 272.5 ms median | 146.3 MB working set / 75.6 MB private | Same native app, precompiled ReadyToRun framework/app code. |
| Windows C# NativeAOT | 153.39 MB self-contained; 9.04 MB `.exe` | 161.6 ms median | 109.6 MB working set / 55.2 MB private | Same native app, AOT/trimming-compatible publish. |
| TypeScript TUI, Windows | 0.07 MB app JS plus 64.75 MB `node.exe` if bundled | 243.3 ms one-shot render | 42.4 MB working set / 29.0 MB private | One Node process; no desktop renderer. |
| WebUI server only, Windows | 66.93 MB package / 27.12 MB ZIP | 529.7 ms HTTP-ready | 43.1 MB working set / 24.2 MB private | One Node server process; not a GUI by itself. |
| Browser-backed WebUI, warm Brave | Same WebUI package plus user browser | 529.7 ms server-ready + 210.7 ms browser target observed | About +149.3 MB working set including server | Reuses already-open browser process set. |
| Browser-backed WebUI, cold Brave | Same WebUI package plus user browser | 578.6 ms server-ready; 597.7 ms browser title-ready | 541.2 MB working set / 304.2 MB private | Browser memory dominates. |
| Windows Tauri WebUI | 92.19 MB app payload estimate | 824.2 ms window shown; 1.85 s WebUI rendered | 429.6 MB working set / 388.3 MB private | Tauri app + bundled Node + six WebView2 children + console host in benchmark build. |
| Windows Tauri, Edge already open | Same Tauri artifact | 1.29 s rendered vs 1.33 s no-Edge control | 388.6 MB working set / 182.6 MB private excluding Edge baseline | Still creates its own WebView2 child process set. |
| Windows Dioxus WebUI | 88.88 MB package / 33.76 MB ZIP | 1.01 s window shown; 1.24 s rendered | 436.2 MB working set / 218.1 MB private | Rust shell + bundled Node + seven WebView2 children. |
| Windows Electron WebUI | 351.06 MB package; 216.08 MB `.exe` | 1.54 s window shown; 1.64 s rendered | 414.0 MB working set / 394.4 MB private | Five Electron processes; Chromium/Node bundled in Electron. |
| Windows Flutter desktop | 27.63 MB Release folder | 184.1 ms median window-ready | 72.6 MB working set / 67.1 MB private | Flutter desktop runner with Material-rendered bundle UI; no browser/WebView/Node in the measured app. |
| Windows Slint Rust | 11.44 MB package / 4.53 MB ZIP | 6.2 ms median internal UI-ready | 28.1 MB working set / 8.4 MB private | Native Rust/Slint renderer using software backend in benchmark host. |
| Windows NodeGui / Qt | 509.84 MB NodeGui/Qode dependency payload estimate; app JS is 0.02 MB | 557.1 ms median Qt window shown | 103.7 MB working set / 83.5 MB private | One measured `qode.exe` process using Qt widgets from TypeScript. |
| macOS Gio research app | 8.1 MB release folder including sample bundle; 6.4 MB stripped executable | 343.7 ms first-frame marker | 186.7 MB RSS after 2 s hold | Go/Gio native renderer with bundle loader and action/control shell; no browser/WebView/Node. |
| macOS React Native research app | 31.4 MB `.app`; 20.7 MB executable | 169.4 ms native app-delegate/bridge marker; rendered timing pending | 95.6 MB RSS after 2 s hold | `react-native-macos` runner with generated native macOS project and bundled JS; lifecycle marker is not visual readiness. |

## Follow-up implementation and macOS benchmark pass

This pass imported the Flutter and Slint research apps into the local worktree and made both more comparable with the mature surfaces:

- Flutter now has explicit data-source execution, dynamic options/rows/value payload handling, command optional-argument rendering, config-setting dropdown/toggle rendering, and a setup panel that can run setup scripts.
- Slint now models setup steps, section/control data-source metadata, config settings, page/row actions, command previews, action buttons, and terminal output for action execution.
- SwiftUI gained a benchmark-only startup marker and a startup optimization in `BundleSessionLoader` / `BundleSourceLoader`.

### SwiftUI startup root cause and fix

The slower SwiftUI startup was not caused by SwiftUI view rendering alone. The app did more synchronous pre-window work than the WebUI shells:

1. `ContentView.init` called `BundleSessionLoader.bootstrap` before the first window could finish appearing.
2. `bootstrap` loaded the bundle once as a probe and then loaded it again for the selected localization.
3. `prepareBundleWorkspace` recopied the demo bundle into Application Support on every launch, preserving only the `runtime` directory.
4. Config bootstrap and initial config loading also ran synchronously before the first view tree completed.

The fix keeps behavior but removes avoidable work:

- Reuse the default bundle load when the selected localization is default/unspecified instead of parsing the bundle twice.
- Write a source fingerprint into the prepared workspace and skip the copy pass when the bundle source has not changed.
- Keep the benchmark marker argument-gated so normal app behavior and output are unchanged.

### New macOS benchmark results

See `aidocs/gui-toolkit-macos-benchmark-run.md` for the dedicated benchmark record with commands, readiness definitions, and caveats.

| Surface | Build/command | Size | Startup/readiness | Memory | Notes |
| --- | --- | ---: | ---: | ---: | --- |
| Improved SwiftUI macOS app | `make build-swift-release`, launched via LaunchServices with `--benchmark-output` | 9.2 MB `.app` | 852.8 ms median external wall-clock to first `WindowGroup.onAppear`; 518.1 ms median to `ContentView` initialized | Not resampled in this pass | Previous documented first-window number was 1.51 s, so the workspace/load optimization materially improved the measured path. |
| macOS Slint research app | `make build-slint-release`; `gui-for-cli-slint --benchmark --once` | 12 MB release folder including sample bundle | 80.9 ms median internal UI-ready after warm cache | 30.0 MB median max RSS | The metric is Slint component/UI-ready, not external window-visible time. |
| macOS Flutter research app | `make benchmark-flutter-macos` after installing Flutter 3.41.9 | 39.4 MB `.app` on disk; Flutter build reports 41.2 MB | 223.0 ms median external wall-clock to bundle content-ready marker; 35.1 ms median from Dart `main` to content-ready | 112.8 MB median RSS at marker | Flutter's generated macOS sandbox had to be disabled for the research app so it can read the local bundle path and write the benchmark marker. |

The new SwiftUI and Flutter numbers are still not directly apples-to-apples with Tauri/Electron/WebUI page-rendered metrics because they use benchmark markers inside the app. They are useful for this investigation because they measure the paths that matter for each native renderer: SwiftUI app launch through synchronous bundle/session initialization and first window appearance, and Flutter process launch through bundle content readiness.

## LOC and app-structure analysis

These counts are current source-file counts from the local worktree after importing the Flutter and Slint prototypes. They intentionally exclude generated folders, build outputs, `target`, `node_modules`, Flutter `.dart_tool`, and lockfiles.

| Surface | Source files | LOC | Structure notes |
| --- | ---: | ---: | --- |
| SwiftUI shared/macOS | 45 | 4,305 | `Apps/macOS` is a tiny app entrypoint over `Apps/Shared`, which contains bundle chrome, page/control renderers, data-source loading, setup orchestration, terminal/process handling, accessibility annotations, and reusable controls. |
| WebView shell | 1 | 312 | `Apps/WebViewShell/Shell.swift` is a compact custom macOS shell that starts the Node backend and hosts WebUI in WKWebView. |
| Flutter | 9 | 2,046 | `Apps/Flutter/lib/main.dart` hosts app state and routing, while `src/` contains widgets, bundle loading, startup benchmarking, localization, models, data-source execution, and command rendering helpers. |
| Slint | 3 | 795 | `Apps/Slint/src` keeps the Slint UI/action runner thin while shared Rust bundle, setup, terminal, and process logic lives under `Apps/RustShared/src`. |
| Windows C# app/core/tests | 25 | 5,296 | `Apps/Windows` contains WinUI shell/pages/controls, `Sources/GUIForCLIWindows.Core` contains bundle/runtime services, and `Tests/GUIForCLIWindows.CoreTests` covers the core layer. |
| WebUI browser/server/TUI | 47 | 7,807 | `WebUI/src` carries browser UI, server APIs, shared rendering/model code, TUI modules, localization, and tests. This is the largest reusable cross-surface codebase. |
| Tauri shell | 2 | 311 | `WebUI/src-tauri` is a thin Rust wrapper around the existing WebUI build plus bundled Node/runtime resources. |

The LOC split explains several architecture tradeoffs. SwiftUI and Windows C# are larger because they implement native controls, setup, process, and data-source behavior directly. Tauri and WKWebView are small because they delegate almost everything to WebUI. Flutter is now in the middle: it has its own native-rendered UI and command/data-source behavior, but still less platform-specific infrastructure than the mature SwiftUI/WinUI paths. Slint remains small because it is still a research renderer with action execution and setup visibility, not a fully mature app shell.

## Why the sizes look the way they do

### Native platform apps

SwiftUI and WinUI look small when measured as app-specific payload because most UI/runtime capability is supplied by the operating system or installed platform runtimes. That is a real deployment advantage, not a benchmark trick. On macOS, SwiftUI links Apple frameworks from the OS. On Windows, the clean self-contained WinUI/.NET publish is large because it carries .NET, Windows App SDK, WinUI, DirectML/ONNX-related payload, and support DLLs; the framework-dependent app-specific payload is only about 0.62 MB without symbols.

The NativeAOT C# branch is important because it changes the Windows native tradeoff: it improved startup and memory while reducing the self-contained publish from the clean/ReadyToRun shape. It required source-generated JSON metadata and trim/AOT-compatible WinUI selector code, so it is the fastest/smallest native Windows direction when compatibility holds.

### WebView shells

WKWebView, Tauri, and Dioxus are not expensive because the app UI code is large. They are expensive because they keep a browser-like renderer and a backend runtime in the product architecture. On macOS, system WebKit keeps this reasonably lean. On Windows, WebView2 creates multiple `msedgewebview2.exe` children, so memory is dominated by the WebView2 process set rather than by Rust shell code. Dioxus trims the shell executable/package a bit compared with Tauri, but both still pay the same Node and WebView2 architecture cost.

The warm-Edge Tauri PR was useful because it tested an easy assumption: if Edge is already open, maybe the second WebView2 app becomes much cheaper. The answer was mostly no for this app. Startup moved a little, but Tauri still launched its own WebView2 children and did not get a material app-process-set RAM reduction.

### Electron

Electron is the most self-contained web-app distribution. That is also why it is huge: each app carries Chromium, Node, V8, helpers, and application resources. Its startup is not terrible and Windows runtime memory was competitive with Tauri in one environment, but its package size and process model make it a benchmark/fallback rather than the preferred shell.

### Flutter and Slint

Flutter and Slint are the most interesting open toolkit PRs because they avoid the browser/WebView/Node renderer architecture. Flutter ships its engine and app code, resulting in a 27.63 MB Windows Release folder and very fast startup in the prototype. Slint compiles a native Rust renderer with the app and sample bundle, producing the smallest package and memory numbers so far.

The caveat is parity. The follow-up Flutter app now renders core controls, script-backed data sources, setup state, terminal output, and rendered bundle commands, but native path picking and polish remain follow-ups. The follow-up Slint app now exposes setup state, data-derived action models, action execution, and terminal output, but its startup metric is still internal component/UI readiness rather than externally observed window-ready.

### Gio and React Native

Gio and React Native were added as macOS-capable research worktrees after identifying PR #27 and PR #24. Gio is attractive on disk because it builds to a small stripped Go executable plus copied sample resources, and it emits a real first-frame metric from the native render loop. The first macOS smoke benchmark showed higher RSS than expected, so it needs more profiling before it can be considered a footprint winner.

React Native macOS is viable from a build/tooling standpoint after moving the branch to the `react-native-macos` 0.81.7 stack and adding a generated macOS runner. Its `.app` size and RSS are reasonable in the first run, but the current startup marker is native lifecycle/bridge setup rather than visual React content. It should stay in research until it has parity features and a rendered-content/video startup measurement.

### NodeGui / Qt

NodeGui gives a surprisingly good runtime shape because it avoids Chromium/WebView processes and renders native Qt widgets from the shared TypeScript model. The problem is packaging. The measured app-specific TypeScript output is tiny, but `node_modules/@nodegui/nodegui` and `@nodegui/qode` account for roughly 510 MB before optimized installer work. Unless that payload can be reduced dramatically, NodeGui is a useful architecture benchmark rather than a distribution candidate.

### Browser-backed WebUI and TUI

The TUI proves the shared model can be very cheap when no desktop renderer is involved. Browser-backed WebUI is also useful when a Chromium browser is already open, but it is not a controlled app experience. Cold browser launch moves too much memory into the product path, even if the WebUI server itself is small.

## Architecture conclusions

1. **Primary installed desktop path should stay native per platform.** SwiftUI is the right macOS default. Windows C# WinUI is still the most complete Windows app, and the NativeAOT PR makes it substantially more attractive if the optimized path stays reliable.
2. **Best cross-platform native-rendered experiment is Flutter, with Slint as the low-footprint research path.** Flutter has the best balance of measured Windows startup, memory, package size, and near-term feature parity among the open toolkit PRs. Slint is the footprint winner but needs much more app behavior before it can be compared as a product surface. Gio and React Native are useful research branches, but their current macOS numbers are not as decision-ready because parity and visual readiness evidence lag behind Flutter/Slint.
3. **WebView shells are best when WebUI reuse matters more than memory.** WKWebView on macOS is acceptable and compact. Tauri/Dioxus on Windows are convenient and package smaller than Electron, but WebView2 memory/process cost is structural.
4. **Dioxus vs Tauri is not a fundamental runtime win.** Dioxus produced a slightly smaller package and faster measured render in its PR, but it still has the same Node + WebView2 process model, so it should be considered a packaging/tooling variant, not a different class of architecture.
5. **Electron should remain fallback/benchmark only.** It is easy to package and runtime-competitive in places, but size and memory are too high for the default app.
6. **NodeGui is not worth productizing unless packaging changes.** Its runtime numbers are promising, but the current Qt/Qode payload is worse than Electron before final app packaging.
7. **Browser-backed WebUI is development/preview, not default install UX.** Warm-browser incremental cost is useful; cold-browser memory is not acceptable as the main desktop story.

## Recommended direction

Use this decision stack:

1. Ship/continue **SwiftUI on macOS** and **WinUI C# on Windows**, with **NativeAOT** as the preferred Windows optimized publish once compatibility is proven.
2. Continue **Flutter** as the strongest cross-platform native-rendered prototype, because it has excellent Windows measurements and is closer to app parity than Slint.
3. Keep **Slint** as a research branch for a minimal native Rust renderer, especially if a small, fast, non-web desktop path becomes strategically important.
4. Keep **WKWebView/Tauri/Dioxus** as WebUI reuse shells and benchmarks, not memory-first defaults on Windows.
5. Keep **Electron and NodeGui** as comparison points unless their package-size story changes.

The common reporting rule should be: always publish self-contained size, app-specific payload, startup/readiness definition, memory/process tree, and parity status together. The toolkit ranking changes depending on which dimension is isolated; the product choice should not.
