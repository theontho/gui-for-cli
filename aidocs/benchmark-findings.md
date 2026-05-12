# Benchmark findings

This is the short decision-oriented summary of the GUI benchmark work. See `aidocs/macos-perf-testing.md`, `aidocs/gui-toolkit-macos-benchmark-run.md`, `aidocs/windows-benchmark.md`, `aidocs/windows-benchmark-summary.md`, and `aidocs/flutter-benchmark.md` for full methods, raw measurements, and per-surface notes. For runtime-model analysis (native OS framework reuse vs bundled runtimes like Electron/Node), see `aidocs/runtime-model-research.md`.

## macOS top-line comparison

| Option | Package size | Startup/render time | Practical memory | Best use |
| --- | ---: | ---: | ---: | --- |
| Native SwiftUI macOS app | 9.2 MB | 216 ms median to first window, 265 ms median to bundle UI ready | 67-80 MB physical footprint | Primary long-running desktop app path and fastest measured macOS desktop window. |
| Flutter macOS research app | 39.4 MB `.app` on disk | 1.00 s visual start-to-rendered; 223 ms content-ready marker for internal profiling | 113 MB RSS at marker | Strong cross-platform native-rendered research path; less mature than SwiftUI. |
| Slint macOS research app | 12 MB release folder with sample bundle | 292 ms visual start-to-rendered; 80.9 ms internal UI-ready for profiling | 30 MB median max RSS | Footprint/startup research candidate; app shell is still less complete than SwiftUI/Flutter. |
| Gio macOS research app | 8.1 MB release folder with sample bundle; 6.4 MB executable | 344 ms first Gio frame marker | 187 MB RSS after 2 s hold | Small native-rendered Go prototype; needs more parity work and visual startup capture. |
| React Native macOS research app | 31.4 MB `.app` | 169 ms native app-delegate/bridge marker; visual rendered timing not captured yet | 96 MB RSS after 2 s hold | React Native macOS feasibility branch; benchmark marker is not yet comparable to rendered-content timings. |
| TypeScript TUI | ~109 MB with bundled Node estimate; TUI dist is 96 KB | 385 ms snapshot, 534 ms interactive first frame | 64.6 MB RSS | Fast terminal-first workflow. |
| Native WKWebView shell | 109 MB | 453-718 ms to rendered | 171 MB dirty footprint | Lean macOS-only WebUI app option and WebView baseline. |
| Standalone Tauri WebUI shell | 117.7 MB | 1.04 s visual start-to-rendered; 727 ms marker/window probe for profiling | 152 MB dirty footprint | Portable/self-contained WebUI desktop option. |
| Standalone Electron WebUI shell | 270 MB `.app` | 495-667 ms to rendered | 542 MB aggregate RSS | Cross-platform packaging benchmark/fallback. |
| Flutter macOS desktop app | 40.2 MB `.app` | 801.1 ms median external content-ready, 544.8 ms median internal marker | 127.7 MB RSS | Promising cross-platform native-rendered comparison after the parity pass. |
| Already-open Brave + WebUI | User-installed browser | 474 ms to rendered | +134 MB incremental physical footprint including Node | Fast preview/dev flow when the browser is already open. |
| Cold Brave + WebUI | 417.8 MB Brave + WebUI/Node | 1.85 s server + page | 853 MB Brave physical footprint + 33 MB Node | Avoid as default desktop UX. |
| WebUI server only | 80.1 MB including Node + bundle estimate | 279 ms to `/api/manifest` | 33 MB physical footprint | Backend-only baseline, not a complete GUI. |

## Windows top-line comparison

| Option | Package size | Startup/render time | Practical memory | Best use |
| --- | ---: | ---: | ---: | --- |
| Native Windows C# app | 213.68 MB self-contained publish; 0.62 MB app-only payload without symbols | 335.9 ms median window-ready | 174.2 MB working set, 131.1 MB private memory | Primary packaged Windows desktop path. |
| Windows Dioxus Native WebUI package | 88.88 MB package, 33.76 MB ZIP | 1.24 s median rendered; 1.01 s median window shown | 436.2 MB working set, 218.1 MB private memory | Rust-native WebUI shell benchmark with smaller package than Tauri/Electron. |
| TypeScript TUI | 0.07 MB TUI JS plus Node runtime; measured `node.exe` is 64.75 MB | 243.3 ms median one-shot render | 42.4 MB working set, 29.0 MB private memory | Fast terminal-first workflow. |
| Windows Tauri WebUI shell | 92.19 MB app payload estimate with bundled Node v22.21.1 | 824.2 ms median window shown; 1.85 s median WebUI rendered | 429.6 MB working set, 388.3 MB private memory | Best self-contained Windows WebUI desktop shell, with WebView2 memory cost. |
| Windows WebUI server only | 66.93 MB package, 27.12 MB ZIP | 529.7 ms median HTTP-ready | 43.1 MB working set, 24.2 MB private memory | Lightweight backend baseline, not a complete GUI. |
| Windows WebUI + already-open Brave | Same WebUI package, user-installed browser | 529.7 ms server-ready + 210.7 ms browser target observed | About +149.3 MB working set / +148.0 MB private memory including server | Best browser-backed WebUI path if Chromium is already open. |
| Windows Tauri WebUI + already-open Edge VM spot-check | Same Tauri package; Edge already running separately | 1.29 s median rendered vs 1.33 s no-Edge control on same VM | 388.6 MB working set, 182.6 MB private memory for Tauri process set, excluding Edge baseline | No meaningful second-WebView2 RAM advantage observed. |
| Windows WebUI + cold Brave | Same WebUI package, user-installed browser | 578.6 ms server-ready; 597.7 ms browser title-ready | 541.2 MB working set, 304.2 MB private memory | Avoid as default packaged app experience. |
| Windows Slint Rust app | 11.44 MB package, 4.53 MB ZIP | 6.2 ms median internal UI-ready benchmark | 28.1 MB working set, 8.4 MB private memory | Promising low-footprint native Rust app; rerun package/memory numbers after the fuller action/setup/data-source implementation. |
| Windows Electron WebUI package | 351.06 MB package, 216.08 MB `.exe` | 1.64 s median rendered | 414.0 MB working set, 394.4 MB private memory | Cross-platform packaging benchmark/fallback; runtime-competitive but very large. |
| Flutter Windows desktop app | 27.63 MB Release folder | 184.1 ms median window-ready | 72.6 MB working set, 67.1 MB private memory | Fastest measured Windows desktop startup and smallest self-contained GUI package, pending Windows runner native-path wiring. |
| Windows NodeGui / Qt shell | 509.84 MB NodeGui/Qode dependency payload estimate; app JS is 0.02 MB | 557.1 ms median Qt window shown | 103.7 MB working set, 83.5 MB private memory | Experimental shared-TypeScript Qt benchmark; runtime promising, package payload large. |

## macOS findings

1. The native SwiftUI app is the smallest and lowest-memory distribution by a wide margin, and after launch-work deferral it is also the fastest measured macOS desktop window. The previous 1.51 s result was caused by synchronous bundle/workspace/setup preparation before the first window, not SwiftUI rendering.
2. The Flutter macOS research app is now a serious cross-platform native-rendered candidate: it visually rendered in about 1.00 s, has a 39.4 MB `.app`, and measured 113 MB RSS at its marker after disabling the generated macOS sandbox for local bundle access.
3. The full-featured Flutter macOS app now reaches content-ready in 801.1 ms externally / 544.8 ms internally with a 40.2 MB app and 127.7 MB RSS, making it a credible cross-platform renderer to continue evaluating after SwiftUI/WebUI parity work.
4. Slint has the strongest prototype startup/footprint result so far, with about 292 ms visual start-to-rendered and a 30 MB median max RSS, but its app shell is still less complete than SwiftUI or Flutter.
5. Gio and React Native are now macOS-buildable PR worktree prototypes. Gio is the smaller on-disk result at 8.1 MB including the sample bundle and emitted a 344 ms first-frame marker, but its first RSS sample was high at 187 MB. React Native built into a 31.4 MB `.app` and reached a native lifecycle marker in 169 ms, but that marker is not visual/rendered readiness.
6. The TypeScript TUI is the fastest low-overhead interactive option when terminal UX is acceptable. Its app code is tiny; bundled Node dominates distribution size.
7. The native WKWebView shell is the leanest self-contained WebUI app on macOS. It bundles Node and WebUI assets, renders in a similar single-second range to Tauri, and is useful as both a real build option and a benchmark lower bound for WebView-based UI.
8. Tauri is the best portable WebUI desktop option. It is slightly larger than the custom WKWebView shell and was a little slower in the measured run, but it gives a packaged app model with less custom shell code.
9. Electron startup is competitive, but package size and memory are much higher than WKWebView or Tauri. Keep it as a benchmark/fallback packaging option for now.
10. An already-open browser is fast, but not a controlled app experience. It is useful for preview/development, but depends on browser state and still adds one browser renderer plus the Node server.
11. Cold external browser launch is too expensive for a first-class desktop app path. The cold Brave measurement was dominated by browser memory footprint.

## Windows findings

1. The native Windows C# app is the best Windows desktop result for startup, memory, and process shape. It reaches a usable window in about 336 ms and idles in one process at 174.2 MB working set / 131.1 MB private memory.
2. The Windows native publish size is dominated by framework/runtime payload. The self-contained publish is 213.68 MB, but the measured app-specific payload is only 0.62 MB without symbols and 0.24 MB zipped.
3. The TypeScript TUI is the lightest Windows runtime surface. It renders a one-shot frame in about 243 ms and idles around 42.4 MB working set / 29.0 MB private memory in one Node process.
4. Tauri is now the best self-contained Windows WebUI shell. It gives a controlled desktop WebUI package without depending on a user browser, but WebView2 pushes the settled footprint to roughly 430 MB working set / 388 MB private memory across the app, Node, and WebView2 process set.
5. The Windows WebUI server is relatively lightweight at runtime, but Node dominates package size. The packaged WebUI runtime is 66.93 MB unpacked / 27.12 MB zipped, with `node.exe` accounting for 64.75 MB and the WebUI assets only 0.59 MB.
6. Browser memory dominates the Windows WebUI experience. The already-open Brave path adds about 149 MB working set including the server, while cold Brave settles around 541 MB working set plus the server/browser process set.
7. An already-open Edge session did not materially reduce Tauri/WebView2 RAM in a same-machine VM spot-check. Tauri still launched its own six `msedgewebview2.exe` children and idled around 389 MB working set, excluding the Edge baseline.
8. The Windows Dioxus Native shell materially reduces package size versus Tauri and Electron (88.88 MB vs 92.19 MB and 351.06 MB), but runtime memory is still dominated by WebView2 child processes.
9. The Slint Rust app is the lowest-footprint Windows GUI measurement so far: 11.44 MB packaged, 4.53 MB zipped, and about 28 MB working set. The branch now includes prototype setup execution, action execution, dynamic data-source rendering, and richer controls, so rerun the Windows package/memory pass before treating the old low-footprint numbers as final.
10. The Windows Electron package renders in about 1.64 s and idles around 414 MB working set, making it runtime-competitive with Tauri in this environment. Its 351.06 MB package is still much larger than the packaged WebUI server, Tauri shell, Dioxus shell, and native app publish, so keep it as a packaging benchmark/fallback.
11. The experimental Flutter Windows app is the fastest and smallest measured desktop package in this pass: 184.1 ms median window-ready, 27.63 MB Release folder, and 72.6 MB working set / 67.1 MB private memory. Keep it marked experimental until the Windows runner has the same native path-picking/open-workspace wiring as macOS.
12. The NodeGui/Qt shell reuses the shared TypeScript WebUI core and avoids browser/WebView process overhead, showing a Qt window in about 557 ms and idling around 104 MB working set. Its current NodeGui/Qode dependency payload is about 510 MB unpacked, so it is best treated as an experimental benchmark until packaging is optimized.
13. Keep ReadyToRun disabled for the current Windows app publish until the WinRT/.NET publish crash is resolved upstream or with a version change.

## Recommendation

Keep the installable GUI options split by platform:

1. **macOS SwiftUI app** as the primary native macOS direction and lowest-memory macOS package.
2. **Windows C# app** as the primary native Windows direction and fastest measured desktop startup path.
3. **TypeScript TUI** as the terminal-first low-overhead option.
4. **Native WKWebView shell** as the lean macOS WebUI distribution and benchmark control.
5. **Tauri WebUI shell** as the portable self-contained WebUI desktop distribution, especially for Windows/macOS WebUI packaging when the WebView/WebView2 memory cost is acceptable; an already-open Edge/WebView2-family runtime did not materially reduce Windows idle RAM in the spot-check.
6. **Dioxus Native WebUI shell** as an additional Rust-native benchmark shell with smaller package size than Tauri/Electron.
7. **Slint Rust app** as a low-footprint native benchmark candidate now that the prototype covers action execution, setup support, and dynamic bundle data-source rendering.
8. **Electron WebUI shell** as a cross-platform packaging benchmark/fallback, not the preferred shell while it remains much heavier.
9. **Packaged WebUI server** as a lightweight browser/development/runtime option, especially when users already have a Chromium browser open.
10. **Flutter desktop app** as a promising experimental cross-platform native-rendered comparison with the best measured Windows startup/package/memory numbers so far and a sub-second full-featured macOS content-ready benchmark.
11. **NodeGui/Qt shell** as an experimental shared-TypeScript native-widget benchmark, not a preferred package while the Qt/Qode payload remains large.

Keep **Gio** and **React Native macOS** in the research bucket for now. Both now build on macOS from their PR worktrees, but neither has the parity level and visual startup evidence that Flutter/Slint currently have.

Use browser-backed WebUI as a development/preview surface, not as the main installed-app experience. Avoid cold external browser launch as the default UX on both macOS and Windows because browser memory dominates the cost.
