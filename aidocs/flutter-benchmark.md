# Flutter benchmark notes

Benchmarked on 2026-05-10 in the Windows task environment.

## Current result

The benchmark harness was added and executed with:

```powershell
.\scripts\benchmark-flutter.ps1
```

The environment did not have `flutter` on `PATH`, so no package, startup, or memory numbers could be collected in
this run. The script wrote an `unavailable` result instead of failing the full validation run:

```json
{
  "status": "unavailable",
  "scenario": "Flutter desktop app",
  "reason": "flutter was not found on PATH"
}
```

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
