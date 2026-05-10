# Flutter benchmark notes

Benchmarked on 2026-05-10 in the Windows task environment.

## Current result

The benchmark harness was executed with Flutter 3.41.9 on Windows desktop:

```powershell
.\scripts\benchmark-flutter.ps1
```

| Metric | Result |
| --- | ---: |
| Startup/window-ready samples | 409.0 ms, 176.9 ms, 183.3 ms, 181.5 ms, 184.1 ms, 213.6 ms, 188.8 ms |
| Median startup/window-ready | 184.1 ms |
| Idle working set | 72.6 MB |
| Idle private memory | 67.1 MB |
| Release folder size | 27.63 MB |
| Release folder bytes | 28,969,559 |

```json
{
  "status": "ok",
  "scenario": "Flutter desktop app",
  "samples": 7,
  "medianStartupWindowReadyMs": 184.1,
  "idleWorkingSetMB": 72.6,
  "idlePrivateMemoryMB": 67.1,
  "packageMB": 27.63
}
```

This is the fastest measured Windows desktop startup and the smallest self-contained GUI package currently in the
comparison set. Treat it as an experimental result because the Flutter renderer is not yet feature-complete with
the native SwiftUI, Windows, or WebUI renderers.

## Harness behavior

`scripts/benchmark-flutter.ps1` stages `Apps/Flutter` under `out\flutter-benchmark\project`, runs
`flutter create --platforms=windows` in that staging directory, runs `flutter pub get` and `flutter test`, builds
a Windows Release app with `GFC_REPO_ROOT` and `GFC_BUNDLE_ROOT` dart defines, then samples:

- startup/window-ready time across multiple launches,
- idle working set and private memory after a short settle interval,
- release package directory size.

The staging flow avoids checking generated Flutter runner files into source control while still producing a normal
Windows desktop Flutter build for benchmark comparison.

## Implementation scope measured by the harness

The Flutter app loads split bundle manifests, page JSON, and TOML string tables directly from the repository. It
renders the core static control set (`text`, `path`, `dropdown`, `toggle`, `checkboxGroup`, `infoGrid`,
`libraryList`, and `configEditor`) with Material widgets and can execute rendered bundle commands while streaming
stdout/stderr into a terminal pane.

Script-backed data sources and native path-picking are intentionally left as parity follow-ups before treating
Flutter as a production app surface.
