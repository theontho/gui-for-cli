# Windows benchmark summary report

This report summarizes the latest Windows benchmark pass. See `docs/ai/platforms/windows.md` for the detailed methods, raw measurements, and per-surface notes.

## Executive summary

The native Windows C# app is the strongest packaged desktop result: the optimized NativeAOT publish reaches a usable window in 161.6 ms median, idles in one process, and uses materially less memory than any WebView or browser-backed GUI path. The TypeScript TUI remains the smallest and fastest runtime surface when terminal UX is acceptable.

The new Windows Tauri result makes it the best self-contained WebUI desktop shell on Windows, but WebView2 dominates its process count and memory. It renders the WebUI in about 1.85 s and idles around 430 MB working set / 388 MB private memory across the app, bundled Node server, and WebView2 child processes. That is a better controlled app experience than depending on a user browser, but it is not competitive with the native Windows app on memory or startup.

Electron is now runtime-benchmarked on Windows. It renders slightly faster than the measured Tauri run and uses similar memory in this environment, but its 351.06 MB package is much larger than the Tauri payload, packaged WebUI server, and native app publish.

## Top-line comparison

| Surface | Startup / readiness | Memory | Process shape | Package / runtime size | Recommendation |
| --- | ---: | ---: | ---: | ---: | --- |
| Native Windows C# app, clean Release | 420.1 ms median window-ready in follow-up run | 154.7 MB working set, 69.7 MB private | 1 process | 213.93 MB self-contained publish; 0.62 MB app-only payload without symbols | Compatibility baseline for packaged Windows desktop path. |
| Native Windows C# app, ReadyToRun | 272.5 ms median window-ready | 146.3 MB working set, 75.6 MB private | 1 process | 258.28 MB self-contained publish | Lower-risk optimized C# release option. |
| Native Windows C# app, NativeAOT | 161.6 ms median window-ready | 109.6 MB working set, 55.2 MB private | 1 process | 153.39 MB self-contained publish; 9.04 MB `.exe` | Fastest and smallest optimized C# release option. |
| TypeScript TUI | 243.3 ms median one-shot render | 42.4 MB working set, 29.0 MB private | 1 process | 0.07 MB TUI JS plus Node runtime; measured `node.exe` is 64.75 MB | Best low-overhead terminal path. |
| WebUI server only | 529.7 ms median HTTP-ready | 43.1 MB working set, 24.2 MB private | 1 process | 66.93 MB packaged, 27.12 MB ZIP with Node and default bundle | Lightweight backend/browser runtime baseline, not a complete GUI. |
| Tauri WebUI shell | 824.2 ms median window shown; 1.85 s median WebUI rendered | 429.6 MB working set, 388.3 MB private | 8 app/runtime processes plus one console host in benchmark build | 92.19 MB app payload estimate with bundled Node v22.21.1 | Best self-contained Windows WebUI shell, but memory-heavy. |
| WebUI + already-open Brave | 529.7 ms server-ready plus 210.7 ms browser target observed | About +149.3 MB working set / +148.0 MB private including server | +1 browser process, +1 server process | Same packaged WebUI payload plus user browser | Best browser-backed WebUI path when Chromium is already open. |
| WebUI + cold Brave | 578.6 ms server-ready; 597.7 ms browser title-ready | 541.2 MB final working set, 304.2 MB private | 9 processes | Same packaged WebUI payload plus user browser | Avoid as default desktop UX. |
| Electron WebUI package | 1.64 s median WebUI rendered; 1.54 s median window shown | 414.0 MB working set, 394.4 MB private | 5 processes | 351.06 MB package, 216.08 MB `.exe` | Cross-platform packaging benchmark/fallback; runtime-competitive but very large. |

## Key findings

1. **Native wins for installed Windows desktop.** The C# app has the fastest measured GUI startup, simplest process model, and substantially lower idle memory than Tauri, Brave, or Electron paths.
2. **NativeAOT is the fastest and smallest optimized C# publish.** The NativeAOT self-contained publish is 153.39 MB and reaches a window in 161.6 ms median; the clean framework-dependent app-specific payload remains only 0.62 MB without symbols and 0.24 MB zipped.
3. **Tauri is the strongest self-contained WebUI shell.** It avoids treating Brave as part of the app experience and has a smaller package than Electron, but WebView2 pushes memory to roughly 430 MB working set.
4. **The WebUI server itself is lightweight.** Runtime memory is close to the TUI, but packaged size is dominated by `node.exe`, not WebUI assets.
5. **Browser-backed WebUI should stay secondary.** Warm Brave is reasonable for development and users already in Chromium, but cold browser launch makes browser memory the dominant cost.
6. **Electron is runtime-competitive but very large.** It rendered in 1.64 s median and idled around 414 MB working set, but its package remains much larger than Tauri, the WebUI server package, and the native app publish.

## Recommended product split

Use the native Windows app as the primary packaged desktop experience, with NativeAOT as the fastest/smallest optimized release, ReadyToRun as a lower-risk optimized release, and clean Release as the compatibility baseline. Keep the TUI for terminal-first and remote workflows. Keep Tauri as the self-contained WebUI desktop option when a browser-like UI is required, but document its WebView2 memory cost clearly. Keep the packaged WebUI server/browser path for development, preview, and users who already prefer Chromium. Keep Electron as a cross-platform packaging benchmark/fallback while it remains much heavier.

## Follow-up measurements

Continue measuring optimized C# publish variants when the Windows App SDK or .NET toolchain changes, because ReadyToRun and NativeAOT behavior depends on those components. If packaged WebUI shells remain in consideration, repeat the Tauri and Electron measurements across more Windows machines and installer forms. Keep measuring the same fields used here: median render readiness, settled working set/private memory, process count, idle CPU, and package size.
