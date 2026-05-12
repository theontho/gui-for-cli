# New macOS app benchmark run

Benchmarked on **2026-05-11 17:57 PDT** on **macOS 26.4.1 (25E253)**, **Apple M1 Pro**, **10 logical CPU cores**, **32 GB RAM**.

This pass covers the **mac-desktop app surfaces** across `main` plus the extra worktrees in `~/src/gui-worktree` and `~/src/gui-worktrees`. It intentionally **excludes** the browser-only WebUI, TUI, and iOS Simulator runs so the comparison stays focused on desktop app platforms.

## SwiftUI rerun after deferred startup fix

Benchmarked again on **2026-05-11 22:13 PDT** after the macOS SwiftUI startup path was changed to defer bundle bootstrap/config loading.

| Surface | Source | Size | Ready metric | Median ready | Median RSS | Samples | Notes |
| --- | --- | ---: | --- | ---: | ---: | ---: | --- |
| SwiftUI macOS app | `main` | 7.86 MB `.app` | external first window | 210.4 ms | 138.4 MB | 5 | Direct executable launch, same readiness class as the original SwiftUI/AppKit measurements. This is a large improvement over the earlier `main` baseline of 1408.3 ms / 159.2 MB. |

- LaunchServices control run (`open -na`): **294.0 ms** median first window, **137.1 MB** median RSS, **5** samples.
- Net change vs the earlier `main` SwiftUI baseline in this note: about **6.7x faster** to first window and about **20.8 MB** lower median RSS.

## Top-line comparison

| Surface | Source | Size | Ready metric | Median ready | Median RSS | Samples | Notes |
| --- | --- | ---: | --- | ---: | ---: | ---: | --- |
| SwiftUI macOS app | `main` | 7.86 MB `.app` | external first window | 210.4 ms | 138.4 MB | 5 | Rerun after the deferred-startup fix. Now close to Swift AppKit on first window and far ahead of the earlier SwiftUI baseline. |
| Swift AppKit remake | `swift-appkit-remake` | 5.43 MB `.app` | external first window | 199.2 ms | 118.2 MB | 5 | Best pure-native macOS startup/size trade-off in this run. |
| ObjC AppKit remake | `objc-appkit-remake` | 3.26 MB `.app` | external first window | 941.9 ms | 103.2 MB | 5 | Smallest app bundle. First launch was a large cold-start outlier (~4.9 s); warm launches were ~0.88-0.95 s. |
| Native WKWebView shell | `main` | 108.92 MB `.app` | internal `webAppRendered` | 514.5 ms | 172.9 MB | 5 | Leanest self-contained WebUI shell on main. |
| Tauri shell | `main` | 118.16 MB `.app` | internal `webNavigationDidFinish` | 422.1 ms | 177.3 MB | 5 | Current build emitted navigation-finished reliably, but did **not** emit the aggregate `webAppRendered` line. |
| Electron shell | `main` | 270.06 MB `.app` | internal `webAppRendered` | 494.6 ms | 671.0 MB | 5 | Startup is fine; package size and memory are still far heavier than every other shell. |
| Flutter desktop app | `pr-23-create-flutter-version-app` | 40.23 MB `.app` | external content-ready marker | 627.3 ms | 123.5 MB | 7 | Branch-provided harness. Cold first launch was slower; warm launches clustered around 0.61-0.64 s. |
| React Native macOS app | `pr-24-add-react-native-version` | 31.43 MB `.app` | native `appDidFinishLaunchingEnd` | 183.0 ms | 95.8 MB | 5 | Fastest native-runner startup, but this is **not** a rendered React-content marker yet. |
| Go Gio app | `pr-27-go-gio-version-benchmark` | 8.45 MB staged release dir | internal `firstFrameRendered` | 265.9 ms | 179.3 MB | 7 | Small staged artifact and very fast first frame; memory landed close to the WebView-shell family. |
| Slint desktop app | `pr-29-add-slint-version-and-benchmarks` | 14.29 MB staged release dir | internal `ui_ready_ms` | 634.1 ms | 132.7 MB | 7 | Full-feature benchmark path with `--benchmark-full`; also reported 144.3 ms median page/data warm-up. |
| Dioxus desktop shell | `pr-30-add-dioxus-native-version-and-benchmarks` | 114.75 MB staged release dir | internal `windowShown` | 455.4 ms | 174.7 MB | 5 | This build never emitted navigation/render completion within the benchmark window; only `windowShown` was stable. |
| NodeGui / Qt shell | `pr-31-add-nodegui-version-and-benchmark` | 112.35 MB runtime estimate (`qode` 112.32 + JS 0.03) | internal `bootToWindowShownMs` | 879.2 ms | 276.7 MB | 5 | Startup came from the built-in benchmark JSON; RSS came from a separate 4 s live run because benchmark mode exits immediately. |

## What stands out

1. **SwiftUI main** improved dramatically after the deferred-startup fix: the rerun landed at **210.4 ms** median to first window and **138.4 MB** median RSS, roughly **6.7x faster** than the earlier SwiftUI baseline in this note.
2. **Swift AppKit** is still the cleanest pure-native macOS result overall: slightly faster than the updated SwiftUI app, smaller on disk, and lower on memory.
3. **React Native** has an impressive native-runner startup marker and the lowest measured RSS here, but it still needs a real rendered-content readiness signal before it can be ranked as a like-for-like UX startup winner.
4. **Gio** remains the fastest of the parity-seeking research renderers with a sub-300 ms first-frame median and an 8.45 MB staged release directory, but its RSS is not especially low.
5. **WKWebView** still looks like the best self-contained WebUI shell on macOS. **Tauri** navigated slightly sooner in this run, but the current build did not emit the final aggregate render metric, so the comparison is not perfectly apples-to-apples.
6. **Electron** is still the obvious outlier: roughly **270 MB** on disk and **671 MB** median aggregate RSS.
7. **Dioxus** and **NodeGui** are promising enough to benchmark, but both still have instrumentation gaps: Dioxus never signaled rendered completion, and NodeGui needs a separate live run to get memory.

## Method notes

- **SwiftUI/AppKit/ObjC AppKit**: direct executable launch, polled first window through `System Events`, then sampled aggregate RSS 1 second later.
- **WKWebView / Tauri / Electron / Gio / Slint / Dioxus / NodeGui / React Native / Flutter**: used each branch's emitted startup metrics where available, then sampled RSS shortly after the chosen ready marker.
- **Tauri** caveat: the build emitted `webNavigationDidFinish_ms` and `webAppRenderedInPage_ms`, but not the aggregate `webAppRendered_ms`, so the table uses navigation-finished as the stable readiness point.
- **React Native** caveat: `appDidFinishLaunchingEnd` is a native app delegate milestone, not proof that the React tree is fully painted.
- **NodeGui** caveat: there is no packaged `.app` yet in this branch; the reported size is a runtime estimate from the checked-in JS output plus the local `qode` runtime binary.
