# Benchmark findings

This is the short decision-oriented summary of the GUI benchmark work. See `aidocs/macos-perf-testing.md`, `aidocs/gui-toolkit-macos-benchmark-run.md`, `aidocs/windows-benchmark.md`, `aidocs/windows-benchmark-summary.md`, and `aidocs/gio-benchmark.md` for full methods, raw measurements, and per-surface notes. For runtime-model analysis (native OS framework reuse vs bundled runtimes like Electron/Node), see `aidocs/runtime-model-research.md`.

## macOS top-line comparison

| Option | Package size | Startup/render time | Practical memory | Best use |
| --- | ---: | ---: | ---: | --- |
| Native SwiftUI macOS app | 9.2 MB | 216 ms median to first window, 265 ms median to bundle UI ready | 67-80 MB physical footprint | Primary long-running desktop app path and fastest measured macOS desktop window. |
| Go Gio full-feature shell | 8.22 MB staged folder; 6.4 MB executable | 463 ms first-frame marker in latest local launch; 285 ms median from prior benchmark run | 187.8 MB RSS from last measured hold | Lightweight cross-platform native small-package candidate with fuller bundle parity. |
| Flutter macOS research app | 39.4 MB `.app` on disk | 1.00 s visual start-to-rendered; 223 ms content-ready marker for internal profiling | 113 MB RSS at marker | Strong cross-platform native-rendered research path; less mature than SwiftUI. |
| Slint macOS research app | 12 MB release folder with sample bundle | 292 ms visual start-to-rendered; 80.9 ms internal UI-ready for profiling | 30 MB median max RSS | Footprint/startup research candidate; app shell is still less complete than SwiftUI/Flutter. |
| React Native macOS research app | 31.4 MB `.app` | 169 ms native app-delegate/bridge marker; visual rendered timing not captured yet | 96 MB RSS after 2 s hold | React Native macOS feasibility branch; benchmark marker is not yet comparable to rendered-content timings. |
| TypeScript TUI | ~109 MB with bundled Node estimate; TUI dist is 96 KB | 385 ms snapshot, 534 ms interactive first frame | 64.6 MB RSS | Fast terminal-first workflow. |
| Native WKWebView shell | 109 MB | 453-718 ms to rendered | 171 MB dirty footprint | Lean macOS-only WebUI app option and WebView baseline. |
| Standalone Tauri WebUI shell | 117.7 MB | 1.04 s visual start-to-rendered; 727 ms marker/window probe for profiling | 152 MB dirty footprint | Portable/self-contained WebUI desktop option. |
| Standalone Electron WebUI shell | 270 MB `.app` | 495-667 ms to rendered | 542 MB aggregate RSS | Cross-platform packaging benchmark/fallback. |
| Already-open Brave + WebUI | User-installed browser | 474 ms to rendered | +134 MB incremental physical footprint including Node | Fast preview/dev flow when the browser is already open. |
| Cold Brave + WebUI | 417.8 MB Brave + WebUI/Node | 1.85 s server + page | 853 MB Brave physical footprint + 33 MB Node | Avoid as default desktop UX. |
| WebUI server only | 80.1 MB including Node + bundle estimate | 279 ms to `/api/manifest` | 33 MB physical footprint | Backend-only baseline, not a complete GUI. |

## Windows top-line comparison

| Option | Package size | Startup/render time | Practical memory | Best use |
| --- | ---: | ---: | ---: | --- |
| Go Gio shell | 8.37 MB package; 6.79 MB `.exe`; 3.19 MB ZIP | 128.0 ms median first frame rendered for the previous thin Windows shell | 70.7 MB working set, 61.4 MB private memory | Lightweight cross-platform native package candidate; rerun Windows after the full-feature parity changes. |
| Native Windows C# app | 213.68 MB self-contained publish; 0.62 MB app-only payload without symbols | 335.9 ms median window-ready | 174.2 MB working set, 131.1 MB private memory | Primary packaged Windows desktop path. |
| TypeScript TUI | 0.07 MB TUI JS plus Node runtime; measured `node.exe` is 64.75 MB | 243.3 ms median one-shot render | 42.4 MB working set, 29.0 MB private memory | Fast terminal-first workflow. |
| Windows Tauri WebUI shell | 92.19 MB app payload estimate with bundled Node v22.21.1 | 824.2 ms median window shown; 1.85 s median WebUI rendered | 429.6 MB working set, 388.3 MB private memory | Best self-contained Windows WebUI desktop shell, with WebView2 memory cost. |
| Windows WebUI server only | 66.93 MB package, 27.12 MB ZIP | 529.7 ms median HTTP-ready | 43.1 MB working set, 24.2 MB private memory | Lightweight backend baseline, not a complete GUI. |
| Windows WebUI + already-open Brave | Same WebUI package, user-installed browser | 529.7 ms server-ready + 210.7 ms browser target observed | About +149.3 MB working set / +148.0 MB private memory including server | Best browser-backed WebUI path if Chromium is already open. |
| Windows Tauri WebUI + already-open Edge VM spot-check | Same Tauri package; Edge already running separately | 1.29 s median rendered vs 1.33 s no-Edge control on same VM | 388.6 MB working set, 182.6 MB private memory for Tauri process set, excluding Edge baseline | No meaningful second-WebView2 RAM advantage observed. |
| Windows WebUI + cold Brave | Same WebUI package, user-installed browser | 578.6 ms server-ready; 597.7 ms browser title-ready | 541.2 MB working set, 304.2 MB private memory | Avoid as default packaged app experience. |
| Windows Electron WebUI package | 351.06 MB package, 216.08 MB `.exe` | 1.64 s median rendered | 414.0 MB working set, 394.4 MB private memory | Cross-platform packaging benchmark/fallback; runtime-competitive but very large. |

## macOS findings

1. The native SwiftUI app is the smallest and lowest-memory distribution by a wide margin, and after launch-work deferral it is also the fastest measured macOS desktop window. The previous 1.51 s result was caused by synchronous bundle/workspace/setup preparation before the first window, not SwiftUI rendering.
2. The fuller Gio shell is now the smallest staged macOS GUI package measured here. It reached a 463 ms first-frame marker in the latest local launch after parity work; use `aidocs/gio-benchmark.md` for Gio-specific caveats and rerun details.
3. The Flutter macOS research app is now a serious cross-platform native-rendered candidate: it visually rendered in about 1.00 s, has a 39.4 MB `.app`, and measured 113 MB RSS at its marker after disabling the generated macOS sandbox for local bundle access.
4. Slint has the strongest prototype startup/footprint result so far, with about 292 ms visual start-to-rendered and a 30 MB median max RSS, but its app shell is still less complete than SwiftUI or Flutter.
5. React Native now builds into a 31.4 MB `.app` and reaches a native lifecycle marker quickly, but that marker is not visual/rendered readiness.
6. The TypeScript TUI is the fastest low-overhead interactive option when terminal UX is acceptable. Its app code is tiny; bundled Node dominates distribution size.
7. The native WKWebView shell is the leanest self-contained WebUI app on macOS. It bundles Node and WebUI assets, renders in a similar single-second range to Tauri, and is useful as both a real build option and a benchmark lower bound for WebView-based UI.
8. Tauri is the best portable WebUI desktop option. It is slightly larger than the custom WKWebView shell and was a little slower in the measured run, but it gives a packaged app model with less custom shell code.
9. Electron startup is competitive, but package size and memory are much higher than WKWebView or Tauri. Keep it as a benchmark/fallback packaging option for now.
10. An already-open browser is fast, but not a controlled app experience. It is useful for preview/development, but depends on browser state and still adds one browser renderer plus the Node server.
11. Cold external browser launch is too expensive for a first-class desktop app path. The cold Brave measurement was dominated by browser memory footprint.

## Windows findings

1. The previous Go Gio benchmark shell is the size/startup leader on Windows. Its packaged footprint is only 8.37 MB, warm launches settle in the 117-146 ms range, and it idles in one process around 70.7 MB working set / 61.4 MB private memory; rerun Windows after the full-feature parity changes.
2. The native Windows C# app remains the most complete Windows-native implementation. It reaches a usable window in about 336 ms and idles in one process at 174.2 MB working set / 131.1 MB private memory.
3. The Windows native publish size is dominated by framework/runtime payload. The self-contained publish is 213.68 MB, but the measured app-specific payload is only 0.62 MB without symbols and 0.24 MB zipped.
4. The TypeScript TUI is the lightest Windows runtime surface. It renders a one-shot frame in about 243 ms and idles around 42.4 MB working set / 29.0 MB private memory in one Node process.
5. Tauri is now the best self-contained Windows WebUI shell. It gives a controlled desktop WebUI package without depending on a user browser, but WebView2 pushes the settled footprint to roughly 430 MB working set / 388 MB private memory across the app, Node, and WebView2 process set.
6. The Windows WebUI server is relatively lightweight at runtime, but Node dominates package size. The packaged WebUI runtime is 66.93 MB unpacked / 27.12 MB zipped, with `node.exe` accounting for 64.75 MB and the WebUI assets only 0.59 MB.
7. Browser memory dominates the Windows WebUI experience. The already-open Brave path adds about 149 MB working set including the server, while cold Brave settles around 541 MB working set plus the server/browser process set.
8. An already-open Edge session did not materially reduce Tauri/WebView2 RAM in a same-machine VM spot-check. Tauri still launched its own six `msedgewebview2.exe` children and idled around 389 MB working set, excluding the Edge baseline.
9. The Windows Electron package renders in about 1.64 s and idles around 414 MB working set, making it runtime-competitive with Tauri in this environment. Its 351.06 MB package is still much larger than the packaged WebUI server, Tauri shell, Gio shell, and native app publish, so keep it as a packaging benchmark/fallback.
10. Keep ReadyToRun disabled for the current Windows app publish until the WinRT/.NET publish crash is resolved upstream or with a version change.

## Recommendation

Keep the installable GUI options split by platform:

1. **macOS SwiftUI app** as the primary native macOS direction and lowest-memory macOS package.
2. **Windows C# app** as the primary native Windows direction and fastest measured desktop startup path.
3. **Go Gio shell** as the lightweight cross-platform native small-package option now that its bundle surface is closer to the SwiftUI/WebUI implementations.
4. **TypeScript TUI** as the terminal-first low-overhead option.
5. **Native WKWebView shell** as the lean macOS WebUI distribution and benchmark control.
6. **Tauri WebUI shell** as the portable self-contained WebUI desktop distribution, especially for Windows/macOS WebUI packaging when the WebView/WebView2 memory cost is acceptable; an already-open Edge/WebView2-family runtime did not materially reduce Windows idle RAM in the spot-check.
7. **Electron WebUI shell** as a cross-platform packaging benchmark/fallback, not the preferred shell while it remains much heavier.
8. **Packaged WebUI server** as a lightweight browser/development/runtime option, especially when users already have a Chromium browser open.

Keep **Flutter, Slint, Gio, and React Native macOS** in the research bucket until each prototype reaches full parity and has repeatable visual startup evidence on its target platforms.

Use browser-backed WebUI as a development/preview surface, not as the main installed-app experience. Avoid cold external browser launch as the default UX on both macOS and Windows because browser memory dominates the cost.
