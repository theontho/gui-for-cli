# Runtime model research: native vs bundled runtimes

This note continues the benchmark research with one specific question:

> Are native runtimes "cheating" on binary size by reusing OS libraries, and do OSes give special optimizations to native stacks versus Electron/web runtimes?

## Short answer

Yes: native apps usually look smaller because they rely on preinstalled platform frameworks/runtime components. That is not measurement error; it is a deployment model advantage.

No: modern desktop OSes generally do **not** apply special, Electron-only optimizations. Electron benefits mostly from the same generic VM/page-cache/process scheduling optimizations available to other apps, while native stacks additionally benefit from deep integration with system frameworks and loader/runtime distribution models.

## Platform findings

## macOS

- Native AppKit/SwiftUI/Foundation/WebKit apps dynamically link to Apple frameworks already present on the system.
- `dyld` shared cache and memory-mapped shared pages reduce duplicate code pages across processes.
- Result: small app bundles can still use large platform capability without shipping those framework binaries.

For our benchmark framing, this explains why the SwiftUI app package is tiny compared to self-contained WebUI shells, while runtime memory can still be competitive.

## Windows

- Native Win32/WinUI/.NET framework-dependent apps can rely on system-provided components (Windows DLL sets, shared framework/runtime installs, WebView2 runtime when used).
- Self-contained distribution (including runtime/framework payload) increases package size substantially.
- Result: "app-specific payload" and "self-contained payload" answer different questions and should both be reported.

For our benchmark framing, this matches our observed split between very small app-specific payload and much larger self-contained publish/package sizes.

## Linux

- Native GTK/Qt/WebKitGTK-style apps typically use ELF shared libraries from distro/runtime packages.
- Shared objects are loaded once into the kernel page cache and reused across processes.
- Containerized models (Flatpak/Snap) can also shift common runtime payload into shared platform runtimes.

For our benchmark framing, Linux-native size/memory comparisons should separate app payload from required runtime base in the same way as Windows.

## Electron/web runtime findings

- Electron packages Chromium + Node + V8 with each app by default, so disk footprint is large unless shared-runtime strategies are introduced externally.
- Electron gets broad OS optimizations (virtual memory, file cache, scheduler, GPU drivers), but these are generic and not a native-stack equivalent of system framework reuse.
- Browser-backed WebUI (already-open browser) can look much better at incremental cost because the browser runtime is already paid for by another process/session.

## Implications for our benchmark interpretation

To keep comparisons fair, report these dimensions separately:

1. **Self-contained install size** (what users download/install for an offline-first packaged app).
2. **App-specific payload size** (code/assets specific to this app, excluding reusable platform/runtime layers when measurable).
3. **Cold-start practical memory** (new process set from closed state).
4. **Warm-start incremental memory** (already-open browser/runtime scenarios).

This avoids mixing deployment-model differences into one "binary size" number and better explains why native, Tauri/WebView, browser-backed WebUI, and Electron each look different.

## Recommendation for this repo

- Keep native app paths as primary packaged desktop experience on each platform.
- Keep Tauri/WKWebView as lighter WebUI shell baselines.
- Keep Electron as cross-platform packaging fallback/benchmark, not primary default.
- Keep browser-backed WebUI as development/preview and warm-browser workflow option.
- Continue publishing both app-specific and self-contained package figures in docs/ai tables.
