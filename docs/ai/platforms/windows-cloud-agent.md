# Cloud agent Windows benchmark notes

Benchmarked on 2026-05-11 on the GitHub/Copilot cloud agent Windows runner.

## Environment

| Item | Value |
| --- | --- |
| OS | Microsoft Windows Server 2025 Datacenter 10.0.26100 |
| CPU | AMD EPYC 7763 64-Core Processor |
| Logical processors | 4 |
| RAM | 16 GB |
| Node / npm | Node v22.22.2 / npm 10.9.7 |
| .NET SDK | 10.0.203 |
| Rust | rustc 1.95.0 |
| Chrome | 147.0.7727.117 |
| Edge | 147.0.3912.86 |
| Brave | Not installed on the runner |

Notes:

- This file is a same-machine cloud-agent companion to `docs/ai/platforms/windows.md`.
- Each startup benchmark used seven launches where the existing benchmark notes used seven launches.
- Browser-backed WebUI rows use Chrome instead of Brave because Brave was not installed on the cloud-agent machine.
- The Tauri and Electron first launch each showed a cold-start outlier; medians are the comparison values below.
- The Electron package was produced with the equivalent direct `npm --prefix platform/typescript exec electron-packager -- ...` command after `.\make.ps1 package -Platform electron` hit a Node `spawn EINVAL` error in this runner.

## Summary comparison

| Scenario | Startup / open time | CPU sample | Working set | Private memory | Process count | Artifact / runtime size |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Windows C# app, Release publish | 380.7 ms median window-ready | 1.74% all-core over 15.0s | 155.7 MB final | 71.0 MB final | 1 | 213.68 MB self-contained publish; 1.91 MB app-only bootstrap payload |
| Tauri WebUI shell, Release | 1.29 s median WebUI rendered; 1.02 s median window shown | 0.08% all-core over 15.1s | 397.1 MB median | 197.8 MB median | 9 app/runtime processes | 92.14 MB app payload estimate with bundled Node v22.21.1 |
| Tauri WebUI shell, Edge already open | 1.28 s median WebUI rendered; 1.02 s median window shown | 0.23% all-core over 15.1s | 394.3 MB median app process set, excluding Edge baseline | 194.7 MB median app process set, excluding Edge baseline | 9 app/runtime processes; Edge baseline was 14 processes | same Tauri artifact and bundled Node v22.21.1 |
| TypeScript TUI | 305.4 ms median one-shot render; interactive frame ready after same startup path | 0.10% all-core over 15.1s | 51.8 MB final interactive | 53.7 MB final interactive | 2 including console host | 0.07 MB TUI JS plus Node runtime; current `node.exe` is 83.04 MB |
| WebUI server only | 1.05 s median HTTP-ready | idle memory sampled after 2.0s | 63.6 MB final | 65.3 MB final | 2 including console host | 85.29 MB unpacked / 32.57 MB zipped with `node.exe`, WebUI assets, built-in strings, and default bundle |
| WebUI, cold Chrome launch | 1.09 s server-ready; 15.41 s browser title-ready | 4.05% all-core over 15.1s | 455.0 MB final, 503.1 MB peak | 228.0 MB final, 247.0 MB peak | 10 including server and console host | same packaged WebUI payload |
| WebUI, already-open Chrome with Google tab | 1.04 s server-ready, then 45.2 ms browser target/title observed | 2.06% all-core over 15.2s | +61.5 MB final including server, from 574.9 MB Chrome baseline to 636.3 MB combined final | +57.6 MB final including server, from 254.0 MB Chrome baseline to 311.6 MB combined final | +1 process including server/console net change | same packaged WebUI payload |
| Electron WebUI package | 848.3 ms median WebUI rendered; 755.2 ms median window shown | 0.21% all-core over 15.1s | 385.4 MB median | 203.6 MB median | 5 | 351.06 MB package; 216.08 MB `.exe` |

## Windows C# app

- Artifact: `out\windows-publish\GUIForCLIWindows.exe`
- Build: `.\make.ps1 release-build -Platform windows`
- Startup sample count: 7 launches
- Window-ready times: 422.1 ms, 371.9 ms, 380.7 ms, 375.5 ms, 374.7 ms, 397.7 ms, 367.3 ms
- Average window-ready time: 384.3 ms
- Median window-ready time: 380.7 ms
- 15.0 second idle resource sample:
  - Average CPU: 1.74% across all logical cores, 6.97% of one core
  - Working set: 155.8 MB median, 155.7 MB final, 155.8 MB peak
  - Private memory: 71.0 MB median, 71.0 MB final, 71.2 MB peak
  - Process count: 1
- Size measurements:
  - Clean publish size: 213.68 MB
  - EXE size: 0.28 MB
  - Framework-dependent publish size: 78.37 MB
  - App-specific bootstrap payload: 1.91 MB
  - App-specific bootstrap ZIP: 0.59 MB
  - Framework/runtime payload remaining in the framework-dependent publish: 76.46 MB

## Tauri WebUI shell

- Artifact: `platform\typescript\web\packagers\tauri\target\release\gui-for-cli-webui-tauri.exe`, staged resources under `platform\typescript\web\packagers\tauri\target\release`, and the Windows NSIS installer copied to `out\release\tauri`
- Build: `python tools\platform.py package tauri` to produce the installer, or `npm --prefix platform/typescript run tauri:build` for the raw Tauri bundle
- Runtime: bundled official Node v22.21.1
- Startup sample count: 7 launches
- Median startup metrics:
  - Server `/api/manifest` ready: 537.4 ms
  - Window shown: 1.02 s
  - Tauri/WebView navigation finished: 1.11 s
  - WebUI page rendered: 1.29 s
- WebUI page rendered times: 4.35 s, 1.46 s, 1.29 s, 1.27 s, 1.24 s, 1.25 s, 1.26 s
- 15.1 second idle resource sample:
  - Average CPU: 0.08% across all logical cores, 0.31% of one core
  - Median working set: 397.1 MB
  - Median private memory: 197.8 MB
  - Final working set: 386.5 MB
  - Final private memory: 186.4 MB
  - Median process count: 9
- Size measurements:
  - Tauri executable: 8.07 MB
  - Estimated app payload before installer compression: 92.14 MB

### Already-open Edge / second WebView2-family app spot-check

Scenario: Microsoft Edge was launched first with a fresh temporary profile and a `google.com` tab. The same benchmark-enabled Tauri release executable was then launched seven times while Edge remained open.

- Edge baseline before Tauri launches:
  - Working set: 690.6 MB
  - Private memory: 327.6 MB
  - Process count: 14
- Edge-already-open Tauri run, 7 launches:
  - Median server `/api/manifest` ready: 541.2 ms
  - Median window shown: 1.02 s
  - Median Tauri/WebView navigation finished: 1.12 s
  - Median WebUI page rendered: 1.28 s
  - WebUI page rendered times: 1.29 s, 1.23 s, 1.28 s, 1.32 s, 1.23 s, 1.25 s, 1.25 s
  - Median working set: 394.3 MB, excluding the already-running Edge baseline
  - Median private memory: 194.7 MB, excluding the already-running Edge baseline
  - Median process count: 9
  - Median CPU: 0.23% across all logical cores, 0.93% of one core

Interpretation: already-open Edge again did not materially reduce Tauri/WebView2 RAM on this same machine. The Tauri process set stayed around 394 MB working set / 195 MB private memory.

## TypeScript TUI

- Artifact: `platform\typescript\dist\tui\main.js`
- Build: `npm --prefix platform/typescript run build`
- Runtime: Node v22.22.2
- Launch target: `node platform\typescript\dist\tui\main.js --bundle examples\WGSExtract --once --no-setup`
- One-shot sample count: 7 launches
- One-shot render-and-exit times: 332.5 ms, 273.9 ms, 305.4 ms, 295.3 ms, 311.0 ms, 269.7 ms, 268.2 ms
- Average one-shot render-and-exit time: 293.7 ms
- Median one-shot render-and-exit time: 305.4 ms
- Output size: 4,564 bytes per one-shot render
- 15.1 second interactive idle resource sample:
  - Average CPU: 0.10% across all logical cores, 0.41% of one core
  - Working set: 55.9 MB median, 51.8 MB final
  - Private memory: 58.0 MB median, 53.7 MB final
  - Median process count: 2 including console host
- Size measurements:
  - `platform\typescript\dist\tui`: 0.07 MB
  - Current package `node.exe`: 83.04 MB

## WebUI server and browser-backed WebUI

- Artifact: `platform\typescript\dist`
- Build: `npm --prefix platform/typescript run build`
- Runtime: Node v22.22.2
- Browser substitute: Chrome 147.0.7727.117 because Brave was unavailable

### Server-only benchmark

Scenario: production WebUI server only, launched as `node platform\typescript\dist\server\main.js --bundle examples\WGSExtract --port <port>`, then polled until `GET /api/manifest` returned HTTP 200.

- Startup sample count: 7 launches
- HTTP-ready times: 1,081.5 ms, 1,040.5 ms, 1,052.7 ms, 1,036.2 ms, 1,047.7 ms, 1,042.9 ms, 1,046.8 ms
- Average HTTP-ready time: 1,049.8 ms
- Median HTTP-ready time: 1,047.7 ms
- Memory after 2 seconds:
  - Working set: 63.6 MB
  - Private memory: 65.3 MB
  - Process count: 2 including console host

### Windows WebUI package

Generated with `.\make.ps1 package -Platform webui`.

- Package directory size: 85.29 MB
- Package ZIP size: 32.57 MB
- Included `node.exe`: 83.04 MB
- Included WebUI assets: 0.66 MB
- Included default WGS Extract bundle: 1.41 MB
- Included built-in strings: 0.17 MB

### WebUI with cold Chrome launch

Scenario: production WebUI server plus a new Chrome window for `http://127.0.0.1:<port>/`, using a fresh temporary profile and remote debugging for readiness detection.

- Server ready time: 1,090.1 ms
- Browser target available time: 15,404.5 ms
- Browser title ready time: 15,406.3 ms
- 15.1 second combined idle resource sample, server plus browser:
  - Average CPU: 4.05% across all logical cores, 16.20% of one core
  - Working set: 503.1 MB peak, 455.0 MB final
  - Private memory: 247.0 MB peak, 228.0 MB final
  - Median process count: 10
- Browser-only spot sample:
  - Working set: 392.4 MB
  - Private memory: 165.7 MB
  - Process count: 7

### WebUI with already-open Chrome

Scenario: Chrome was already running with a `google.com` tab open in a fresh temporary profile. The WebUI production server was started first and was already listening when the WebUI URL was opened through Chrome's remote debugging endpoint.

- Server ready time: 1,043.4 ms
- WebUI browser target observed: 45.2 ms after opening the URL
- Browser title ready time: 45.2 ms after opening the URL
- Baseline Chrome memory with Google tab:
  - Working set: 574.9 MB
  - Private memory: 254.0 MB
  - Process count: 11
- Final combined memory after opening WebUI tab, including server:
  - Working set: 636.3 MB
  - Private memory: 311.6 MB
  - Median process count: 12
- Estimated full incremental WebUI memory including server:
  - Working set: +61.5 MB final
  - Private memory: +57.6 MB final
- CPU over 15.2 seconds after opening:
  - Average CPU: 2.06% across all logical cores, 8.24% of one core

## Windows Electron package

- Package command: `npm --prefix platform/typescript exec electron-packager -- platform\typescript\.cache\electron-package\app "GUI for CLI Electron" --platform=win32 --arch=x64 --out=out\windows-electron --overwrite --quiet`
- Package root: `out\windows-electron\GUI for CLI Electron-win32-x64`
- App executable: `out\windows-electron\GUI for CLI Electron-win32-x64\GUI for CLI Electron.exe`
- Startup sample count: 7 launches
- Median startup metrics:
  - Electron app ready: 36.6 ms
  - Server `/api/manifest` ready: 549.0 ms
  - Electron navigation finished: 728.0 ms
  - Window shown: 755.2 ms
  - WebUI page rendered: 848.3 ms
- WebUI page rendered times: 1.57 s, 816.6 ms, 735.2 ms, 715.8 ms, 728.7 ms, 848.3 ms, 920.0 ms
- 15.1 second idle resource sample:
  - Average CPU: 0.21% across all logical cores, 0.83% of one core
  - Median working set: 385.4 MB
  - Median private memory: 203.6 MB
  - Median process count: 5
- Package directory size: 351.06 MB
- App executable size: 216.08 MB
- Staged app resources before Electron runtime: 2.25 MB
