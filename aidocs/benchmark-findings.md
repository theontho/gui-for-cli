# Benchmark findings

This is the short decision-oriented summary of the GUI benchmark work. See `aidocs/macos-perf-testing.md`, `aidocs/windows-benchmark.md`, and `aidocs/windows-benchmark-summary.md` for full methods, raw measurements, and per-surface notes. For runtime-model analysis (native OS framework reuse vs bundled runtimes like Electron/Node), see `aidocs/runtime-model-research.md`.

## macOS top-line comparison

| Option | Package size | Startup/render time | Practical memory | Best use |
| --- | ---: | ---: | ---: | --- |
| Native SwiftUI macOS app | 9.2 MB | 1.51 s to first window | 67-80 MB physical footprint | Primary long-running desktop app path. |
| TypeScript TUI | ~109 MB with bundled Node estimate; TUI dist is 96 KB | 385 ms snapshot, 534 ms interactive first frame | 64.6 MB RSS | Fast terminal-first workflow. |
| Native WKWebView shell | 109 MB | 453-718 ms to rendered | 171 MB dirty footprint | Lean macOS-only WebUI app option and WebView baseline. |
| Standalone Tauri WebUI shell | 117.7 MB | 727 ms to rendered | 152 MB dirty footprint | Portable/self-contained WebUI desktop option. |
| Standalone Electron WebUI shell | 270 MB `.app` | 495-667 ms to rendered | 542 MB aggregate RSS | Cross-platform packaging benchmark/fallback. |
| Already-open Brave + WebUI | User-installed browser | 474 ms to rendered | +134 MB incremental physical footprint including Node | Fast preview/dev flow when the browser is already open. |
| Cold Brave + WebUI | 417.8 MB Brave + WebUI/Node | 1.85 s server + page | 853 MB Brave physical footprint + 33 MB Node | Avoid as default desktop UX. |
| WebUI server only | 80.1 MB including Node + bundle estimate | 279 ms to `/api/manifest` | 33 MB physical footprint | Backend-only baseline, not a complete GUI. |

## Windows top-line comparison

| Option | Package size | Startup/render time | Practical memory | Best use |
| --- | ---: | ---: | ---: | --- |
| Native Windows C# app, clean Release | 213.93 MB self-contained publish; 0.62 MB app-only payload without symbols | 420.1 ms median window-ready in follow-up run | 154.7 MB working set, 69.7 MB private memory | Compatibility baseline for packaged Windows desktop path. |
| Native Windows C# app, ReadyToRun | 258.28 MB self-contained publish | 272.5 ms median window-ready | 146.3 MB working set, 75.6 MB private memory | Lower-risk optimized C# release option. |
| Native Windows C# app, NativeAOT | 153.39 MB self-contained publish; 9.04 MB `.exe` | 161.6 ms median window-ready | 109.6 MB working set, 55.2 MB private memory | Fastest and smallest optimized C# release option. |
| TypeScript TUI | 0.07 MB TUI JS plus Node runtime; measured `node.exe` is 64.75 MB | 243.3 ms median one-shot render | 42.4 MB working set, 29.0 MB private memory | Fast terminal-first workflow. |
| Windows Tauri WebUI shell | 92.19 MB app payload estimate with bundled Node v22.21.1 | 824.2 ms median window shown; 1.85 s median WebUI rendered | 429.6 MB working set, 388.3 MB private memory | Best self-contained Windows WebUI desktop shell, with WebView2 memory cost. |
| Windows WebUI server only | 66.93 MB package, 27.12 MB ZIP | 529.7 ms median HTTP-ready | 43.1 MB working set, 24.2 MB private memory | Lightweight backend baseline, not a complete GUI. |
| Windows WebUI + already-open Brave | Same WebUI package, user-installed browser | 529.7 ms server-ready + 210.7 ms browser target observed | About +149.3 MB working set / +148.0 MB private memory including server | Best browser-backed WebUI path if Chromium is already open. |
| Windows Tauri WebUI + already-open Edge VM spot-check | Same Tauri package; Edge already running separately | 1.29 s median rendered vs 1.33 s no-Edge control on same VM | 388.6 MB working set, 182.6 MB private memory for Tauri process set, excluding Edge baseline | No meaningful second-WebView2 RAM advantage observed. |
| Windows WebUI + cold Brave | Same WebUI package, user-installed browser | 578.6 ms server-ready; 597.7 ms browser title-ready | 541.2 MB working set, 304.2 MB private memory | Avoid as default packaged app experience. |
| Windows Electron WebUI package | 351.06 MB package, 216.08 MB `.exe` | 1.64 s median rendered | 414.0 MB working set, 394.4 MB private memory | Cross-platform packaging benchmark/fallback; runtime-competitive but very large. |

## macOS findings

1. The native SwiftUI app remains the smallest and lowest-memory distribution by a wide margin. Its measured first-window time was slower than the WebUI shells, but its 9.2 MB app size and 67-80 MB physical footprint make it the best default for a long-running desktop app.
2. The TypeScript TUI is the fastest low-overhead interactive option when terminal UX is acceptable. Its app code is tiny; bundled Node dominates distribution size.
3. The native WKWebView shell is the leanest self-contained WebUI app on macOS. It bundles Node and WebUI assets, renders in the same sub-second range as Tauri, and is useful as both a real build option and a benchmark lower bound for WebView-based UI.
4. Tauri is the best portable WebUI desktop option. It is slightly larger than the custom WKWebView shell and was a little slower in the measured run, but it gives a packaged app model with less custom shell code.
5. Electron startup is competitive, but package size and memory are much higher than WKWebView or Tauri. Keep it as a benchmark/fallback packaging option for now.
6. An already-open browser is fast, but not a controlled app experience. It is useful for preview/development, but depends on browser state and still adds one browser renderer plus the Node server.
7. Cold external browser launch is too expensive for a first-class desktop app path. The cold Brave measurement was dominated by browser memory footprint.

## Windows findings

1. The native Windows C# app is the best Windows desktop result for startup, memory, and process shape. The optimized NativeAOT publish reached a usable window in 161.6 ms median and idled in one process at 109.6 MB working set / 55.2 MB private memory in the follow-up run.
2. The Windows native publish size is dominated by framework/runtime payload in the clean and ReadyToRun variants. NativeAOT produced the smallest self-contained publish in the follow-up run at 153.39 MB, while the measured app-specific framework-dependent payload remains only 0.62 MB without symbols and 0.24 MB zipped.
3. The TypeScript TUI is the lightest Windows runtime surface. It renders a one-shot frame in about 243 ms and idles around 42.4 MB working set / 29.0 MB private memory in one Node process.
4. Tauri is now the best self-contained Windows WebUI shell. It gives a controlled desktop WebUI package without depending on a user browser, but WebView2 pushes the settled footprint to roughly 430 MB working set / 388 MB private memory across the app, Node, and WebView2 process set.
5. The Windows WebUI server is relatively lightweight at runtime, but Node dominates package size. The packaged WebUI runtime is 66.93 MB unpacked / 27.12 MB zipped, with `node.exe` accounting for 64.75 MB and the WebUI assets only 0.59 MB.
6. Browser memory dominates the Windows WebUI experience. The already-open Brave path adds about 149 MB working set including the server, while cold Brave settles around 541 MB working set plus the server/browser process set.
7. An already-open Edge session did not materially reduce Tauri/WebView2 RAM in a same-machine VM spot-check. Tauri still launched its own six `msedgewebview2.exe` children and idled around 389 MB working set, excluding the Edge baseline.
8. The Windows Electron package renders in about 1.64 s and idles around 414 MB working set, making it runtime-competitive with Tauri in this environment. Its 351.06 MB package is still much larger than the packaged WebUI server, Tauri shell, and native app publish, so keep it as a packaging benchmark/fallback.
9. Keep all three Windows C# release paths available: clean Release for compatibility, ReadyToRun for a lower-risk optimized build, and NativeAOT for the fastest/smallest optimized package.

## Recommendation

Keep the installable GUI options split by platform:

1. **macOS SwiftUI app** as the primary native macOS direction and lowest-memory macOS package.
2. **Windows C# app** as the primary native Windows direction and fastest measured desktop startup path.
3. **TypeScript TUI** as the terminal-first low-overhead option.
4. **Native WKWebView shell** as the lean macOS WebUI distribution and benchmark control.
5. **Tauri WebUI shell** as the portable self-contained WebUI desktop distribution, with the caveat that an already-open Edge/WebView2-family runtime did not materially reduce Windows idle RAM in the spot-check.
6. **Electron WebUI shell** as a cross-platform packaging benchmark/fallback, not the preferred shell while it remains much heavier.
7. **Packaged WebUI server** as a lightweight browser/development/runtime option, especially when users already have a Chromium browser open.

Use browser-backed WebUI as a development/preview surface, not as the main installed-app experience. Avoid cold external browser launch as the default UX on both macOS and Windows because browser memory dominates the cost.
