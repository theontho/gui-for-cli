# Go Gio benchmark notes

Benchmarked on 2026-05-10 on Windows 11 Pro with an AMD Ryzen 5 5600X, 12 logical processors, and on 2026-05-11 on macOS from the staged release binary.

## Summary comparison

| Scenario | Startup / open time | CPU sample | Working set | Private memory | Process count | Artifact / runtime size |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Go Gio full-feature shell (macOS, last successful first-frame run before terminal/settings parity) | 285.0 ms median first frame rendered; 2.0 ms median window configured; 1.9 ms median bundle loaded | Not sampled | 187.8 MB RSS median | Not sampled | 1 | 8.22 MB current package; 6.64 MB current executable |
| Go Gio benchmark shell (Windows, previous thin shell) | 128.0 ms median first frame rendered; 22.2 ms median window configured; 15.2 ms median bundle loaded | 0.26% all-core over 15.0s | 70.7 MB median | 61.4 MB median | 1 | 8.37 MB package; 6.79 MB `.exe`; 3.19 MB ZIP |

The current Gio surface now decodes and renders the richer bundle model used by the SwiftUI and WebUI apps: config editors, setup status/runs, data-source-backed options and library tables with retry affordances, row actions, action visibility/disabled predicates, confirmations, file-state placeholders, disk-space prechecks, localized labels with runtime language switching, standard icon/theme/font preferences, persisted bundle state, sidebar/terminal visibility chrome, tabbed command output, copy-to-clipboard, action cancellation, setup streaming, and exit-code status in one Gio process.

The most recent local macOS benchmark attempt could not collect a valid first-frame sample because Gio `v0.9.0` panicked during native window creation before `firstFrameRendered`. A minimal Gio window reproduced the same `runtime/cgo: misuse of an invalid Handle` failure in this environment, so the current first-frame row above remains the last valid launch measurement and should be rerun on a macOS GUI session that can create Gio windows.

## Build and package

Generate the portable Windows Gio package with:

```powershell
.\make.ps1 package -Platform gio
```

This target runs `go mod tidy`, builds `exp-platform\go\gio` with `go build -trimpath -ldflags "-s -w"`, stages the default `examples\WGSExtract` bundle plus built-in string tables, and writes:

- `out\windows-gio\package\gui-for-cli-gio.exe`
- `out\windows-gio\GUIForCLIGio-win-x64.zip`
- `out\windows-gio\GUIForCLIGio-win-x64-package.json`

Measured package sizes:

- Package directory: 8.368 MB
- ZIP: 3.191 MB
- Executable: 6.788 MB
- Included default WGS Extract bundle: 1.409 MB
- Included built-in strings: 0.170 MB

Generate and benchmark the macOS staged Gio binary with:

```sh
make benchmark ARGS='gio'
```

This target builds `out/release/gio/gui-for-cli-gio`, stages the default WGS Extract bundle and built-in strings, launches the app repeatedly, reads the `metric <name>_ms=<value>` startup lines, samples RSS after first frame, and writes `out/release/gio/benchmark-macos.json`.

The POSIX Makefile builds Gio with `GIO_GO ?= GOTOOLCHAIN=go1.25.0 go` to match the Windows CI benchmark toolchain; override `GIO_GO` only when validating a different Go/Gio combination deliberately.

Measured macOS staged sizes:

- Package directory: 8.217 MB
- Executable: 6.639 MB
- Included default WGS Extract bundle: 1.402 MB
- Included built-in strings: 0.166 MB

## macOS full-feature launch samples

These samples are the last successful macOS first-frame run. The current expanded parity build stages at the sizes above, but the local macOS window benchmark is blocked by the Gio window-creation panic described in the summary.

| Run | Bundle loaded | Window configured | First frame rendered | RSS |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 1.8 ms | 1.8 ms | 260.6 ms | 187.8 MB |
| 2 | 7.7 ms | 7.7 ms | 298.1 ms | 187.7 MB |
| 3 | 2.0 ms | 2.0 ms | 315.9 ms | 188.3 MB |
| 4 | 1.8 ms | 1.8 ms | 285.0 ms | 187.5 MB |
| 5 | 2.1 ms | 2.1 ms | 301.0 ms | 189.9 MB |
| 6 | 1.9 ms | 2.0 ms | 271.5 ms | 187.4 MB |
| 7 | 1.7 ms | 1.7 ms | 279.9 ms | 187.9 MB |

Median macOS results:

- Bundle loaded: 1.9 ms
- Window configured: 2.0 ms
- First frame rendered: 285.0 ms
- RSS after first frame settle: 187.8 MB
- Process count: 1

## Windows previous thin-shell method

- Runtime: Go 1.25.0, Gio `gioui.org` v0.9.0
- Launch target: packaged `out\windows-gio\package\gui-for-cli-gio.exe`
- Sample count: 7 launches
- Startup metrics: the Gio app prints `metric <name>_ms=<value>` for `bundleLoaded`, `windowConfigured`, and `firstFrameRendered`
- Idle resource sample: after the first rendered frame, the process idles for 15 seconds before sampling CPU, working set, and private memory
- Process count: sampled through the launched process handle; the Gio shell stays in a single process

The first two runs were slower than the steady-state launches, which appears consistent with initial shader/font cache warm-up. Warm runs stabilized in the 117-146 ms range to the first rendered frame.

## Windows previous thin-shell launch samples

| Run | Bundle loaded | Window configured | First frame rendered | CPU all-core | Working set | Private memory |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 38.5 ms | 47.4 ms | 665.8 ms | 0.2604% | 68.2 MB | 59.3 MB |
| 2 | 252.9 ms | 259.1 ms | 490.9 ms | 0.4687% | 71.5 MB | 61.9 MB |
| 3 | 15.2 ms | 21.4 ms | 122.0 ms | 0.2083% | 72.1 MB | 62.3 MB |
| 4 | 14.0 ms | 22.2 ms | 117.5 ms | 0.3125% | 68.3 MB | 59.0 MB |
| 5 | 47.2 ms | 52.3 ms | 146.0 ms | 0.2604% | 70.7 MB | 61.4 MB |
| 6 | 14.6 ms | 20.2 ms | 124.1 ms | 0.3124% | 72.1 MB | 63.1 MB |
| 7 | 13.4 ms | 19.2 ms | 128.0 ms | 0.2083% | 68.1 MB | 57.6 MB |

Median results:

- Bundle loaded: 15.2 ms
- Window configured: 22.2 ms
- First frame rendered: 128.0 ms
- CPU: 0.2604% across all logical cores over 15.0 seconds
- Working set: 70.7 MB
- Private memory: 61.4 MB
- Process count: 1

## Interpretation

1. The Gio shell is by far the smallest packaged Windows GUI artifact in this repository so far. At 8.37 MB unpacked and 3.19 MB zipped, it avoids both the .NET/Windows App SDK payload of the C# app and the Node/WebView/Chromium payloads of the WebUI shells.
2. Warm-start startup is excellent. Once the initial caches are populated, the Gio shell consistently renders its first frame in roughly 0.12-0.15 seconds.
3. Runtime memory is also lean for a desktop GUI surface: about 70.7 MB working set / 61.4 MB private memory in one process after settling.
4. The fuller Gio implementation costs more memory on macOS than the older Windows thin-shell measurement, but it still keeps the package size near 8 MB while rendering a feature-comparable bundle surface in under 300 ms median on the last valid macOS run.
5. Gio remains a strong lightweight cross-platform native packaging candidate, especially when package size and startup latency matter more than framework-specific OS integration.
