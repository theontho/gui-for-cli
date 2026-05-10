# Windows and WebUI benchmark notes

Benchmarked on 2026-05-10 on Windows 11 Pro with an AMD Ryzen 5 5600X, 12 logical processors.

## Summary comparison

| Scenario | Startup / open time | CPU sample | Working set | Private memory | Process count | Artifact / runtime size |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Windows C# app, Release publish | 335.9 ms median window-ready | 0.27% all-core over 15.2s | 174.2 MB final | 131.1 MB final | 1 | 213.68 MB self-contained publish; 0.62 MB app-only payload without symbols |
| WebUI server only | 529.7 ms median HTTP-ready | idle memory sampled after 2s | 43.1 MB average | 24.2 MB average | 1 | 66.93 MB unpacked / 27.12 MB zipped with `node.exe`, WebUI assets, built-in strings, and default bundle |
| WebUI, cold Brave launch | 578.6 ms server-ready; 597.7 ms browser title-ready | 0.17% all-core over 15.6s | 541.2 MB final, 582.9 MB peak | 304.2 MB final, 337.9 MB peak | 9 | same packaged WebUI payload |
| WebUI, already-open Brave with Google tab | 529.7 ms server HTTP-ready, then 210.7 ms browser target observed | 0.47% all-core over 22.2s | +106.2 MB browser tab; about +149.3 MB including server | +123.8 MB browser tab; about +148.0 MB including server | +1 browser, +1 server | same WebUI artifact |
| Electron WebUI package | not runtime-benchmarked on Windows yet | not measured | not measured | not measured | not measured | 351.04 MB package; 216.08 MB `.exe`; built by cross-packaging `win32-x64` |

Notes: the WebUI package size is from `.\make.ps1 package-webui`, which copies `node.exe`, compiled WebUI assets, built-in strings, and the default WGS Extract bundle. The cold WebUI row includes the production Node server plus Brave. The warm-browser row reports browser-tab memory over an already-open Brave baseline with a `google.com` tab, then adds server-only memory for the estimated full WebUI cost.

## Interpretation and recommendations

The native Windows app is the best startup and memory result for a desktop-first package: it reaches a usable window in about 336 ms and idles at 174 MB working set in one process. Its self-contained Windows App SDK/.NET publish is 213.68 MB unpacked even after disabling ReadyToRun, but the app-specific payload is only about 0.62 MB without symbols when framework/runtime components are treated as separate redistributables.

The WebUI server itself is lightweight at runtime. It takes about 530 ms to become HTTP-ready and idles around 43 MB working set / 24 MB private memory. Bundling Node dominates package size: the measured `node.exe` is 64.75 MB, while the packaged WebUI runtime assets are only 0.59 MB. The generated Windows WebUI package is 66.93 MB unpacked and 27.12 MB zipped when it includes `node.exe`, WebUI assets, built-in strings, and the default WGS Extract bundle.

The browser dominates WebUI memory. A cold Brave launch plus WebUI settles around 541 MB working set, while an already-open Brave instance adds roughly 106 MB working set and 124 MB private memory for the WebUI tab. Including the Node server, the warm-browser WebUI path costs about 149 MB working set and 148 MB private memory. Treat the warm-browser case as the best realistic WebUI UX if the user already has a Chromium browser running; treat the cold-browser case as the cost of making the browser part of the app experience.

Recommendations:

- Prefer the native Windows app for the packaged desktop experience when startup latency, idle memory, and predictable process shape matter most.
- Keep the WebUI as a low-friction browser-based option, especially for development, remote/local workflows, or users who already live in Brave/Chromium.
- If shipping WebUI as a package, bundle only the compiled WebUI/runtime files plus a pinned Node runtime; do not include `node_modules` unless a future runtime dependency requires it.
- Consider a slimmer embedded runtime option before treating WebUI as the primary packaged Windows app. The current `node.exe`-based package is 66.93 MB unpacked / 27.12 MB zipped before compression by an installer, and browser memory remains external and much larger than the server.
- Keep Electron as a Windows packaging comparison only until it is runtime-benchmarked on Windows hardware. Cross-packaging produced a 351.04 MB `win32-x64` package with a 216.08 MB `.exe`, much larger than the packaged WebUI server and larger than the native Windows self-contained publish.
- Keep ReadyToRun disabled for the current Windows app publish until the WinRT/.NET publish crash is resolved upstream or with a version change.

## Windows C# app

- Artifact: `out\windows-publish\GUIForCLIWindows.exe`
- Build: Release, x64, self-contained, Windows App SDK self-contained
- Launch target: raw published EXE
- Startup sample count: 7 launches
- Window-ready times: 367.9 ms, 332.7 ms, 334.6 ms, 336.0 ms, 335.9 ms, 334.8 ms, 319.6 ms
- Average window-ready time: 337.4 ms
- Median window-ready time: 335.9 ms
- 15.2 second idle resource sample:
  - Average CPU: 0.27% across all logical cores, 3.18% of one core
  - Working set: 174.2 MB peak, 174.2 MB final
  - Private memory: 131.1 MB peak, 131.1 MB final
  - Process count: 1
- Clean publish size: 213.68 MB
- EXE size: 0.28 MB
- Framework-dependent publish size: 77.08 MB
- App-specific payload without symbols: 0.62 MB
- App-specific payload with symbols: 0.73 MB
- Framework/runtime payload remaining in the framework-dependent publish, excluding app files and symbols: 76.46 MB
- Framework-dependent EXE size: 0.16 MB
- App-specific payload compressed as a ZIP: 0.24 MB
- Estimated runtime-downloading installer size: roughly 1-3 MB with a typical installer framework, or under 1 MB with a very small custom bootstrapper

Note: the original optimized publish used `PublishReadyToRun=true` and crashed before showing a window with WinRT/.NET type-load failures. The benchmark above uses the fixed clean Release publish with ReadyToRun disabled.

Framework-dependent size notes: this publish was created with `SelfContained=false` and `WindowsAppSDKSelfContained=false`. The app-specific payload includes `GUIForCLIWindows.exe`, `GUIForCLIWindows.dll`, `GUIForCLIWindows.Core.dll`, `resources.pri`, runtime/deps JSON, and bundled string resources. The remaining 76.46 MB is mostly framework/runtime payload such as `Microsoft.Windows.SDK.NET.dll`, `onnxruntime.dll`, `DirectML.dll`, and `Microsoft.WinUI.dll`, which should be considered separately from the app binary itself when comparing app code size. Generate this app-only payload with `.\make.ps1 package-bootstrap`; it writes `out\windows-bootstrap\GUIForCLIWindows-win-x64-app.zip` and a companion bootstrap manifest.

Installer estimate: a bootstrap installer that downloads and installs the .NET/Windows App SDK runtime separately only needs to carry the app payload plus installer logic. The measured app-specific payload is 0.62 MB uncompressed and 0.24 MB compressed, so the final installer binary size would be dominated by the installer framework. A normal NSIS/Inno/Wix-style bootstrapper is likely around 1-3 MB before branding/assets; a purpose-built tiny downloader could be under 1 MB.

## WebUI with Brave

- Artifact: `WebUI\dist`
- Build: `npm --prefix WebUI run build`
- Runtime: Node v19.1.0
- Browser: Brave, profile directory `Profile 2` (display name `google`)
- Launch target: production Node server plus a new Brave window for `http://127.0.0.1:8787/`
- Server ready time: 578.6 ms
- Browser target available time: 593.3 ms
- Browser title ready time: 597.7 ms
- 15.6 second combined idle resource sample, server plus browser:
  - Average CPU: 0.17% across all logical cores, 2.01% of one core
  - Working set: 582.9 MB peak, 541.2 MB final
  - Private memory: 337.9 MB peak, 304.2 MB final
  - Process count: 9
- 5.1 second server-only sample:
  - Average CPU: 0.00%
  - Working set: 39.8 MB
  - Private memory: 21.6 MB
  - Process count: 1
- 5.2 second browser-only sample:
  - Average CPU: 0.00%
  - Working set: 501.1 MB
  - Private memory: 282.3 MB
  - Process count: 7
- `WebUI\dist` size: 0.18 MB
- WebUI runtime files excluding `node_modules`: 0.81 MB

Note: the WebUI server initially failed on Node v19.1.0 because `node:fs/promises` did not export `statfs`. The benchmark above uses the compatibility fallback for disk-space checks.

### Server-only benchmark

Scenario: production WebUI server only, launched as `node WebUI\dist\server\main.js --bundle Examples\WGSExtract --port <port>`, then polled until `GET /` returned HTTP 200.

- Runtime: Node v19.1.0 at `C:\Program Files\nodejs\node.exe`
- Startup sample count: 7 launches
- Process start times: 19.8 ms, 10.2 ms, 9.7 ms, 10.6 ms, 9.5 ms, 9.9 ms, 10.2 ms
- HTTP-ready times: 595.5 ms, 531.3 ms, 529.7 ms, 525.2 ms, 526.6 ms, 526.4 ms, 527.0 ms
- Average process start time: 11.4 ms
- Average HTTP-ready time: 537.4 ms
- Median HTTP-ready time: 529.7 ms
- Average memory after 2 seconds:
  - Working set: 43.1 MB
  - Private memory: 24.2 MB
- Size measurements:
  - `WebUI\dist`: 0.18 MB
  - WebUI runtime files excluding `node_modules`: 0.81 MB
  - Full `WebUI` directory including `node_modules`: 25.74 MB
  - `node.exe`: 64.75 MB
  - Node install directory: 75.55 MB
  - Estimated unpacked WebUI package with Node runtime and no `node_modules`: 76.36 MB
  - Estimated unpacked WebUI package with current `node_modules` included: 101.29 MB

### Windows WebUI package

Generate the portable Windows WebUI package with `.\make.ps1 package-webui`. The package copies `node.exe`, compiled WebUI assets, Bootstrap Icons vendor assets, built-in string tables, and the default `Examples\WGSExtract` bundle into `out\windows-webui\package`, writes a `start-webui.ps1` launcher, and creates `out\windows-webui\GUIForCLIWebUI-win-x64.zip`.

- Packaged server validation: `start-webui.ps1 -Port 8799`, then `GET /api/manifest` returned the WGS Extract manifest.
- Runtime: Node v19.1.0 from `C:\Program Files\nodejs\node.exe`
- Package directory size: 66.93 MB
- Package ZIP size: 27.12 MB
- Included `node.exe`: 64.75 MB
- Included WebUI assets: 0.59 MB
- Included default WGS Extract bundle: 1.41 MB
- Included built-in strings: 0.17 MB

### Windows Electron package

Generate the packaged Electron WebUI app with:

```powershell
.\make.ps1 package-electron
```

This target calls the cross-platform Electron packaging script:

```bash
npm --prefix WebUI run electron:package -- --out out\windows-electron --platform win32 --arch x64
```

The package includes the Electron runtime, the Electron shell, compiled WebUI assets, built-in string tables, and the default WGS Extract bundle. It uses Electron's own executable as the app runtime and launches the WebUI backend with `ELECTRON_RUN_AS_NODE=1`, so it does not separately bundle `node.exe`.

Packaging was validated by cross-packaging `win32-x64` from macOS. Runtime startup and memory still need to be measured on Windows hardware.

- Package root: `out\windows-electron\GUI for CLI Electron-win32-x64`
- App executable: `out\windows-electron\GUI for CLI Electron-win32-x64\GUI for CLI Electron.exe`
- Package directory size: 351.04 MB
- App executable size: 216.08 MB
- Staged app resources before Electron runtime: 2.23 MB

### Already-open Brave memory chart

Scenario: Brave was already running with a `google.com` tab open in profile directory `Profile 2` (display name `google`). The WebUI production server was started first and was already listening when the WebUI URL was opened through the default browser path. Browser memory was sampled once per second across the Brave process group that belonged to this benchmark run.

- Runtime: Node v19.1.0
- Server ready time in this run: 563.2 ms
- Median server HTTP-ready time from server-only benchmark: 529.7 ms
- WebUI browser target observed: 210.7 ms after opening the URL
- Page-title readiness: not captured reliably from Brave DevTools target metadata in this run
- Baseline Brave memory with Google tab:
  - Working set: 533.6 MB
  - Private memory: 289.9 MB
  - Process count: 8
- Final Brave memory after opening WebUI tab:
  - Working set: 639.8 MB
  - Private memory: 413.7 MB
  - Process count: 9
- Incremental WebUI tab memory after 20 seconds:
  - Working set: +106.2 MB
  - Private memory: +123.8 MB
  - Extra processes: +1
- Estimated full incremental WebUI memory including server:
  - Working set: +149.3 MB
  - Private memory: +148.0 MB
  - Extra processes: +2
- CPU over 22.2 seconds after opening:
  - Average CPU: 0.47% across all logical cores, 5.69% of one core

| Second | Delta working set | Delta private memory | Total working set | Total private memory | Processes |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | +0.1 MB | +0.1 MB | 533.7 MB | 290.0 MB | 9 |
| 1 | +99.3 MB | +119.1 MB | 632.9 MB | 409.0 MB | 9 |
| 2 | +109.9 MB | +124.6 MB | 643.5 MB | 414.5 MB | 9 |
| 3 | +112.0 MB | +126.6 MB | 645.7 MB | 416.5 MB | 9 |
| 4 | +109.8 MB | +124.0 MB | 643.4 MB | 413.9 MB | 9 |
| 5 | +110.3 MB | +124.0 MB | 644.0 MB | 413.9 MB | 9 |
| 6 | +110.6 MB | +124.4 MB | 644.2 MB | 414.3 MB | 9 |
| 7 | +110.7 MB | +124.2 MB | 644.3 MB | 414.1 MB | 9 |
| 8 | +111.1 MB | +129.1 MB | 644.7 MB | 419.1 MB | 9 |
| 9 | +111.0 MB | +129.1 MB | 644.6 MB | 419.1 MB | 9 |
| 10 | +110.8 MB | +128.9 MB | 644.5 MB | 418.8 MB | 9 |
| 11 | +110.9 MB | +128.9 MB | 644.5 MB | 418.8 MB | 9 |
| 12 | +110.9 MB | +128.9 MB | 644.5 MB | 418.8 MB | 9 |
| 13 | +110.9 MB | +128.9 MB | 644.5 MB | 418.8 MB | 9 |
| 14 | +110.9 MB | +128.9 MB | 644.5 MB | 418.8 MB | 9 |
| 15 | +110.9 MB | +128.9 MB | 644.5 MB | 418.8 MB | 9 |
| 16 | +110.7 MB | +128.2 MB | 644.3 MB | 418.2 MB | 9 |
| 17 | +110.9 MB | +128.3 MB | 644.5 MB | 418.2 MB | 9 |
| 18 | +106.3 MB | +123.8 MB | 640.0 MB | 413.8 MB | 9 |
| 19 | +106.3 MB | +123.8 MB | 639.9 MB | 413.8 MB | 9 |
| 20 | +106.3 MB | +123.8 MB | 639.9 MB | 413.8 MB | 9 |
