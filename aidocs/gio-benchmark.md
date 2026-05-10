# Go Gio benchmark notes

Benchmarked on 2026-05-10 on Windows 11 Pro with an AMD Ryzen 5 5600X, 12 logical processors.

## Summary comparison

| Scenario | Startup / open time | CPU sample | Working set | Private memory | Process count | Artifact / runtime size |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Go Gio benchmark shell | 128.0 ms median first frame rendered; 22.2 ms median window configured; 15.2 ms median bundle loaded | 0.26% all-core over 15.0s | 70.7 MB median | 61.4 MB median | 1 | 8.37 MB package; 6.79 MB `.exe`; 3.19 MB ZIP |

The current Gio surface is a native benchmark shell: it loads the bundle manifest and localized strings, renders pages/controls/actions in a single Gio process, and can launch bundle commands with output captured into the app. It is intentionally much thinner than the Windows C# app, but it is useful as a native cross-platform size/startup baseline.

## Build and package

Generate the portable Windows Gio package with:

```powershell
.\make.ps1 package-gio
```

This target runs `go mod tidy`, builds `Apps\Gio` with `go build -trimpath -ldflags "-s -w"`, stages the default `Examples\WGSExtract` bundle plus built-in string tables, and writes:

- `out\windows-gio\package\gui-for-cli-gio.exe`
- `out\windows-gio\GUIForCLIGio-win-x64.zip`
- `out\windows-gio\GUIForCLIGio-win-x64-package.json`

Measured package sizes:

- Package directory: 8.368 MB
- ZIP: 3.191 MB
- Executable: 6.788 MB
- Included default WGS Extract bundle: 1.409 MB
- Included built-in strings: 0.170 MB

## Method

- Runtime: Go 1.24.13, Gio `gioui.org` v0.9.0
- Launch target: packaged `out\windows-gio\package\gui-for-cli-gio.exe`
- Sample count: 7 launches
- Startup metrics: the Gio app prints `metric <name>_ms=<value>` for `bundleLoaded`, `windowConfigured`, and `firstFrameRendered`
- Idle resource sample: after the first rendered frame, the process idles for 15 seconds before sampling CPU, working set, and private memory
- Process count: sampled through the launched process handle; the Gio shell stays in a single process

The first two runs were slower than the steady-state launches, which appears consistent with initial shader/font cache warm-up. Warm runs stabilized in the 117-146 ms range to the first rendered frame.

## Launch samples

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
4. The current implementation is still a benchmark shell, not a feature-complete Windows app replacement. It renders the bundle-driven UI and launches actions, but it does not yet match the Windows C# app's native platform integrations or richer control behavior.
5. This makes Gio a strong benchmark/control surface and a promising lightweight cross-platform native packaging option, especially when package size and startup latency matter more than framework-specific OS integration.
