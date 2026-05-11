# Windows benchmark summary report

This report summarizes the latest Windows benchmark pass. See `aidocs/windows-benchmark.md` for the detailed methods, raw measurements, and per-surface notes.

## Executive summary

The native Windows C# app is the strongest packaged desktop result: it reaches a usable window in about 336 ms, idles in one process, and uses materially less memory than any WebView or browser-backed GUI path. The TypeScript TUI remains the smallest and fastest runtime surface when terminal UX is acceptable.

The new Windows Tauri result makes it the best self-contained WebUI desktop shell on Windows, but WebView2 dominates its process count and memory. It renders the WebUI in about 1.85 s and idles around 430 MB working set / 388 MB private memory across the app, bundled Node server, and WebView2 child processes. That is a better controlled app experience than depending on a user browser, but it is not competitive with the native Windows app on memory or startup.

## Top-line comparison

| Surface | Startup / readiness | Memory | Process shape | Package / runtime size | Recommendation |
| --- | ---: | ---: | ---: | ---: | --- |
| Native Windows C# app | 335.9 ms median window-ready | 174.2 MB working set, 131.1 MB private | 1 process | 213.68 MB self-contained publish; 0.62 MB app-only payload without symbols | Primary Windows desktop app path. |
| TypeScript TUI | 243.3 ms median one-shot render | 42.4 MB working set, 29.0 MB private | 1 process | 0.07 MB TUI JS plus Node runtime; measured `node.exe` is 64.75 MB | Best low-overhead terminal path. |
| WebUI server only | 529.7 ms median HTTP-ready | 43.1 MB working set, 24.2 MB private | 1 process | 66.93 MB packaged, 27.12 MB ZIP with Node and default bundle | Lightweight backend/browser runtime baseline, not a complete GUI. |
| Tauri WebUI shell | 824.2 ms median window shown; 1.85 s median WebUI rendered | 429.6 MB working set, 388.3 MB private | 8 app/runtime processes plus one console host in benchmark build | 92.19 MB app payload estimate with bundled Node v22.21.1 | Best self-contained Windows WebUI shell, but memory-heavy. |
| WebUI + already-open Brave | 529.7 ms server-ready plus 210.7 ms browser target observed | About +149.3 MB working set / +148.0 MB private including server | +1 browser process, +1 server process | Same packaged WebUI payload plus user browser | Best browser-backed WebUI path when Chromium is already open. |
| WebUI + cold Brave | 578.6 ms server-ready; 597.7 ms browser title-ready | 541.2 MB final working set, 304.2 MB private | 9 processes | Same packaged WebUI payload plus user browser | Avoid as default desktop UX. |
| Electron WebUI package | Not runtime-benchmarked on Windows yet | Not measured | Not measured | 351.04 MB package, 216.08 MB `.exe` | Packaging comparison only until runtime measurements exist. |

## Key findings

1. **Native wins for installed Windows desktop.** The C# app has the fastest measured GUI startup, simplest process model, and substantially lower idle memory than Tauri, Brave, or Electron paths.
2. **The native app size is mostly framework/runtime payload.** The self-contained publish is 213.68 MB, but the app-specific payload is only 0.62 MB without symbols and 0.24 MB zipped.
3. **Tauri is the strongest self-contained WebUI shell.** It avoids treating Brave as part of the app experience and has a smaller package than Electron, but WebView2 pushes memory to roughly 430 MB working set.
4. **The WebUI server itself is lightweight.** Runtime memory is close to the TUI, but packaged size is dominated by `node.exe`, not WebUI assets.
5. **Browser-backed WebUI should stay secondary.** Warm Brave is reasonable for development and users already in Chromium, but cold browser launch makes browser memory the dominant cost.
6. **Electron remains unproven on Windows runtime.** The package is already much larger than the Tauri payload and native app publish; it needs native Windows startup and memory data before any recommendation changes.

## Recommended product split

Use the native Windows app as the primary packaged desktop experience. Keep the TUI for terminal-first and remote workflows. Keep Tauri as the self-contained WebUI desktop option when a browser-like UI is required, but document its WebView2 memory cost clearly. Keep the packaged WebUI server/browser path for development, preview, and users who already prefer Chromium. Keep Electron as a packaging benchmark until Windows runtime measurements justify a stronger role.

## Follow-up measurements

The main remaining gap is a native Windows runtime benchmark for the Electron package. If Electron is still being considered as a cross-platform fallback, measure the same fields used for the other shells: median render readiness, settled working set/private memory, process count, and idle CPU over a 15 second settle window.
