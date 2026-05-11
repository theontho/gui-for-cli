# Benchmark findings

This is the short decision-oriented summary of the GUI benchmark work. See `aidocs/macos-perf-testing.md` and `aidocs/windows-benchmark.md` for full methods, raw measurements, and per-surface notes. For runtime-model analysis (native OS framework reuse vs bundled runtimes like Electron/Node), see `aidocs/runtime-model-research.md`.

## macOS top-line comparison

| Option | Package size | Startup/render time | Practical memory | Best use |
| --- | ---: | ---: | ---: | --- |
| Native SwiftUI macOS app | 9.2 MB | 216 ms median to first window, 265 ms median to bundle UI ready | 67-80 MB physical footprint | Primary long-running desktop app path and fastest measured macOS desktop window. |
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
| Native Windows C# app | 213.68 MB self-contained publish; 0.62 MB app-only payload without symbols | 335.9 ms median window-ready | 174.2 MB working set, 131.1 MB private memory | Primary packaged Windows desktop path. |
| Windows WebUI server only | 66.93 MB package, 27.12 MB ZIP | 529.7 ms median HTTP-ready | 43.1 MB working set, 24.2 MB private memory | Lightweight backend baseline, not a complete GUI. |
| Windows WebUI + already-open Brave | Same WebUI package, user-installed browser | 529.7 ms server-ready + 210.7 ms browser target observed | About +149.3 MB working set / +148.0 MB private memory including server | Best browser-backed WebUI path if Chromium is already open. |
| Windows Tauri WebUI shell | 92.19 MB app payload estimate | 1.85 s median rendered | 429.6 MB working set, 388.3 MB private memory | Self-contained WebUI desktop shell when native UI is not the target. |
| Windows Tauri WebUI + already-open Edge VM spot-check | Same Tauri package; Edge already running separately | 1.29 s median rendered vs 1.33 s no-Edge control on same VM | 388.6 MB working set, 182.6 MB private memory for Tauri process set, excluding Edge baseline | No meaningful second-WebView2 RAM advantage observed. |
| Windows WebUI + cold Brave | Same WebUI package, user-installed browser | 578.6 ms server-ready; 597.7 ms browser title-ready | 541.2 MB working set, 304.2 MB private memory | Avoid as default packaged app experience. |
| Windows Electron WebUI package | 351.06 MB package, 216.08 MB `.exe` | 1.64 s median rendered | 414.0 MB working set, 394.4 MB private memory | Cross-platform packaging benchmark/fallback; runtime-competitive but very large. |

## macOS findings

1. The native SwiftUI app is the smallest and lowest-memory distribution by a wide margin, and after launch-work deferral it is also the fastest measured macOS desktop window. The previous 1.51 s result was caused by synchronous bundle/workspace/setup preparation before the first window, not SwiftUI rendering.
2. The TypeScript TUI is the fastest low-overhead interactive option when terminal UX is acceptable. Its app code is tiny; bundled Node dominates distribution size.
3. The native WKWebView shell is the leanest self-contained WebUI app on macOS. It bundles Node and WebUI assets, renders in the same sub-second range as Tauri, and is useful as both a real build option and a benchmark lower bound for WebView-based UI.
4. Tauri is the best portable WebUI desktop option. It is slightly larger than the custom WKWebView shell and was a little slower in the measured run, but it gives a packaged app model with less custom shell code.
5. Electron startup is competitive, but package size and memory are much higher than WKWebView or Tauri. Keep it as a benchmark/fallback packaging option for now.
6. An already-open browser is fast, but not a controlled app experience. It is useful for preview/development, but depends on browser state and still adds one browser renderer plus the Node server.
7. Cold external browser launch is too expensive for a first-class desktop app path. The cold Brave measurement was dominated by browser memory footprint.

## Windows findings

1. The native Windows C# app is the best Windows desktop result for startup, memory, and process shape. It reaches a usable window in about 336 ms and idles in one process at 174.2 MB working set / 131.1 MB private memory.
2. The Windows native publish size is dominated by framework/runtime payload. The self-contained publish is 213.68 MB, but the measured app-specific payload is only 0.62 MB without symbols and 0.24 MB zipped.
3. The Windows WebUI server is relatively lightweight at runtime, but Node dominates package size. The packaged WebUI runtime is 66.93 MB unpacked / 27.12 MB zipped, with `node.exe` accounting for 64.75 MB and the WebUI assets only 0.59 MB.
4. Browser memory dominates the Windows WebUI experience. The already-open Brave path adds about 149 MB working set including the server, while cold Brave settles around 541 MB working set plus the server/browser process set.
5. An already-open Edge session did not materially reduce Tauri/WebView2 RAM in a same-machine VM spot-check. Tauri still launched its own six `msedgewebview2.exe` children and idled around 389 MB working set, excluding the Edge baseline.
6. The Windows Electron package renders in about 1.64 s and idles around 414 MB working set, making it runtime-competitive with Tauri in this environment. Its 351.06 MB package is still much larger than the packaged WebUI server, Tauri shell, and native app publish, so keep it as a packaging benchmark/fallback.
7. Keep ReadyToRun disabled for the current Windows app publish until the WinRT/.NET publish crash is resolved upstream or with a version change.

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
