# Windows WebView2 wrapper benchmark

Benchmark run for the native Windows WebView2 wrapper mode added to `GUIForCLIWindows` (`--webview-shell`).

## Command

```powershell
.\make.ps1 benchmark-webview2 -BenchmarkIterations 7
```

## Environment

- Date: 2026-05-14
- Platform: GitHub Actions `windows-latest`
- App executable: `exp-platform\windows\dotnet\GUIForCLIWindows\bin\x64\Release\net10.0-windows10.0.19041.0\win-x64\GUIForCLIWindows.exe`
- Bundle: `examples\WGSExtract`

## Startup medians (7 launches)

- `appSetupStarted`: **64.8 ms**
- `nodeProcessStarted`: **98.6 ms**
- `windowShown`: **136.1 ms**
- `serverManifestReady`: **431.9 ms**
- `webNavigationDidFinish`: **654.2 ms**
- `webAppRendered`: **750.4 ms**

`webAppRendered` samples (ms): 795.4, 737.1, 781.5, 827.0, 653.3, 725.4, 750.4

## Idle sample (15.1s)

- CPU (all cores): **0.00%**
- Working set: **104.1 MB**
- Private memory: **26.1 MB**
- Process count sampled from app-root process tree: **1**

## Artifact size snapshot

- Release output directory: **157.96 MB**
- App executable: **0.28 MB**

## Notes

- The benchmark parses in-app `metric <name>_ms=` logs and computes medians.
- Idle process-tree sampling currently uses descendants of the wrapper app process ID; on hosted runners this under-reports detached runtime processes (for example, separate WebView2 process groups).
