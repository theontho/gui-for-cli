# macOS perf testing notes

This document records repeatable local profiling methods and observed results for GUI for CLI surfaces on macOS. The focus is post-launch overhead outside of running bundle CLI commands: startup, idle CPU, memory footprint, and packaged size.

## Summary and recommendation

| Option | Installed/package size | Time to rendered/ready | Practical memory | Idle CPU | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| Native SwiftUI macOS app | 9.2 MB | 1.51 s to first window | 67-80 MB physical footprint | ~0.01% | Lowest memory and smallest app, but current first-window timing is slower than WebUI shells. |
| WebUI server only | 80.1 MB including Node + bundle estimate | 279 ms to `/api/manifest` | 33 MB physical footprint | 0.00% | Backend-only number; not a user-visible GUI by itself. |
| Already-open Brave + WebUI | No app bundle; depends on installed Brave | 474 ms to rendered | +134 MB incremental physical footprint including Node | Brave avg 0.22%, Node 0.00% | Fastest browser route if the browser is already running; not a controlled app experience. |
| Cold Brave + WebUI | Brave app is 417.8 MB plus WebUI/Node | 1.85 s server + page | 853 MB Brave physical footprint + 33 MB Node | settles near 0% | Too heavy for a first-class app experience. |
| Native WKWebView shell + bundled Node | 109 MB bundled `.app` | 453-718 ms to rendered | 171 MB dirty footprint | ~0.01% | Fast self-contained app-like WebUI path; macOS-only and intentionally small. |
| Standalone Tauri WebUI shell | 117.7 MB bundled `.app` | 727 ms to rendered | 152 MB dirty footprint | ~0.00% | Most portable WebUI-app option: self-contained install, fast startup, modest memory. |

Recommendation:

1. Keep the **native SwiftUI app** as the lowest-memory, smallest-package path and the best fit for long-running desktop use.
2. Keep the **native WKWebView shell** as the lean macOS WebUI build option and benchmark lower bound. It is self-contained, renders in the same sub-second range as Tauri, and has a smaller bundle.
3. Keep the **standalone Tauri WebUI shell** as the most portable WebUI-app option. It is self-contained for non-developer machines, starts in under a second, and uses far less memory than a cold full browser.
4. Treat **already-open browser WebUI** as a useful preview/development mode, not the primary app distribution. It is fast and has low incremental cost when Brave is already running, but it depends on user browser state.
5. Do not use **cold external browser launch** as the default desktop experience; the memory cost is too high.

## Environment and general method

- Built from `/Users/mac/src/gui-for-cli` on macOS.
- WebUI assets are built with `npm --prefix WebUI run build`.
- macOS app release builds use:

  ```bash
  ./scripts/tuist.sh generate --no-open
  xcodebuild -workspace GUIForCLI.xcworkspace \
    -scheme GUIForCLIMac \
    -configuration Release \
    -derivedDataPath DerivedData \
    -destination 'platform=macOS' \
    build CODE_SIGNING_ALLOWED=NO
  ```

- Startup timing uses `time.perf_counter_ns()` around process launch and readiness probes.
- WebUI server readiness is measured with `curl` against `/` and `/api/manifest`.
- WebUI browser readiness is measured by launching Brave with remote debugging and polling DevTools `/json/list` for the WebUI page target.
- macOS app readiness is measured by polling System Events for the first app window.
- Idle CPU/RSS uses repeated `ps -p <pid> -o rss=,%cpu=` samples after settling.
- Physical memory uses `/usr/bin/footprint`; this is preferred over aggregate RSS for multi-process browser measurements because RSS double-counts shared mapped pages.
- `sample <pid> 3 -file ...` and `vmmap -summary <pid>` are used for short idle stack/memory profile snapshots.

## Release macOS app baseline

Build artifact:

| Item | Size |
| --- | ---: |
| `DerivedData/Build/Products/Release/GUI for CLI.app` | 9.2 MB |
| `GUI for CLI.app/Contents/MacOS/GUI for CLI` | 7.8 MB |

Repeated launch results, direct executable launch:

| Metric | Result |
| --- | ---: |
| Process alive | avg 33.7 ms, min 31.8 ms, max 36.8 ms |
| First window | avg 1.51 s, min 1.48 s, max 1.56 s |
| Launch-window RSS | avg 149 MB |
| Settled RSS | avg 134 MB |
| Settled idle CPU | avg 0.01%, max 0.20% |
| `sample` physical footprint | 67.4 MB, peak 80.1 MB |

Short idle stack sampling showed the app blocked in the normal AppKit/CoreFoundation event loop.

## WebUI server-only baseline

Build artifacts:

| Item | Size |
| --- | ---: |
| `WebUI/dist` | 236 KB |
| `WebUI/dist/server/main.js` | 11.4 KB |
| `WebUI/dist/client/app.js` | 7.2 KB |
| `WebUI/index.html` | 720 B |
| `WebUI/styles.css` | 20.2 KB |

Repeated launch results for `node WebUI/dist/server/main.js --port <port> --host 127.0.0.1`:

| Metric | Result |
| --- | ---: |
| `/` ready | avg 184 ms, min 169 ms, max 222 ms |
| `/api/manifest` ready | avg 279 ms, min 258 ms, max 316 ms |
| Settled RSS | avg 70 MB |
| `footprint` physical memory | 33 MB |
| Settled idle CPU | 0.00% |

Short idle stack sampling showed Node blocked in `uv__io_poll` / `kevent`.

## WebUI packaged/runtime footprint with Brave

Inputs:

| Item | Size |
| --- | ---: |
| Node direct runtime closure from `otool -L` | 77.9 MB |
| Node Homebrew formula directory | 78.8 MB |
| WebUI dist | 236 KB |
| WebUI static/vendor | 425 KB |
| WGSExtract bundle definition/assets | 1.5 MB |
| Estimated WebUI + direct Node runtime + bundle | 80.1 MB |
| Estimated WebUI + full Node formula dir + bundle | 80.9 MB |
| Installed Brave app bundle | 417.8 MB |

Cold-ish Brave launch from no running Brave processes:

| Metric | Result |
| --- | ---: |
| Node server `/` ready | 169 ms |
| Node server `/api/manifest` ready | 262 ms |
| Brave first process | 127 ms |
| Brave DevTools reachable | 871 ms |
| Brave first window | 1.41 s |
| Brave WebUI page target visible | 1.59 s |
| Combined server then browser/page target | about 1.85 s |
| Node server physical footprint | 33 MB |
| Node server RSS | about 71 MB |
| Brave physical footprint | 853 MB |
| Brave aggregate RSS | about 1.8-2.1 GB |
| Settled Node CPU | 0.00% |
| Settled Brave CPU | 0.00% snapshot; 15s sample avg 0.91%, peak 12.1% during settling |

The practical memory number for Brave is the `footprint` result, not aggregate RSS.

## WebUI with an already-running Brave browser

This benchmark models the lower-cost browser path where Brave is already open. To avoid disturbing the normal browser profile, the benchmark launches a clean temporary Brave profile with remote debugging, waits for it to settle on `about:blank`, records a baseline, then simulates a WebUI "double click" by starting the Node server and opening a new WebUI tab in the already-running Brave instance.

Readiness is measured by polling Chrome DevTools Protocol until the page evaluates:

```js
Boolean(document.querySelector('#app')?.dataset.state === 'ready' && document.title)
```

Baseline already-open Brave:

| Metric | Result |
| --- | ---: |
| Brave process count | 7 |
| Brave RSS | 834 MB |
| Brave physical footprint | 250 MB |

Double-click simulation into existing Brave:

| Metric | Result |
| --- | ---: |
| Node server `/` ready | 162 ms |
| Node server `/api/manifest` ready | 252 ms |
| Page ready after opening tab | 58 ms |
| Total double-click to WebUI rendered | **474 ms** |
| Brave process count after WebUI tab | 8 |
| Brave RSS after WebUI tab | 1.05 GB |
| Brave physical footprint after WebUI tab | 351 MB |
| Incremental Brave physical footprint | **+101 MB** |
| Node server RSS | 71 MB |
| Node server physical footprint | about 33 MB |
| Approx incremental physical footprint including Node | **+134 MB** |
| Settled Brave CPU after WebUI tab | avg 0.22%, max 2.8% over 15s |
| Settled Node CPU | 0.00% |

This is the best browser-based WebUI path so far: it avoids the cold browser launch and full cold browser footprint. From a user-perceived startup perspective it is similar to the native WKWebView shell (~0.47s vs ~0.45-0.72s to rendered), but it depends on an already-running browser and still adds one Brave renderer process plus the Node server.

## Native WKWebView shell

The repository includes a native macOS shell under `Apps/WebViewShell/` to isolate the cost of a small `WKWebView` wrapper around the WebUI. The shell:

- launches the bundled or configured Node runtime with `WebUI/dist/server/main.js --bundle Examples/WGSExtract`;
- waits for `/api/manifest`;
- creates a 1200x800 `WKWebView` window;
- loads `http://127.0.0.1:<port>/`;
- reports the WebUI as rendered when JavaScript sees `#app[data-state="ready"]` and a non-empty `document.title`;
- traps app termination and passes its parent PID to the Node server so profiling runs do not leave a server running.

Build commands:

```bash
make build-webview-shell
make run-webview-shell
make build-webview-release
```

Packaged footprint:

| Item | Size |
| --- | ---: |
| Development shell `.app` | 120 KB |
| Standalone release shell `.app` | 109 MB |
| Bundled Node runtime | 106.5 MB |
| WebUI dist | 236 KB |
| WebUI static/vendor | 425 KB |
| WGSExtract bundle definition/assets | 1.5 MB |

Latest standalone release smoke results from direct shell executable launch:

| Metric | Result |
| --- | ---: |
| App delegate finished launching | 26-35 ms |
| Node process started | 28-46 ms |
| Server `/api/manifest` ready | 151-203 ms |
| Window shown | 242-295 ms |
| `WKNavigationDelegate.didFinish` | 341-423 ms |
| `#app[data-state="ready"]` rendered | **453-718 ms** |

Process set after render from the full profiling run:

| Process | RSS |
| --- | ---: |
| WebView shell app | 92 MB |
| Node server | 71 MB |
| WebKit GPU helper | 44 MB |
| WebKit Networking helper | 23 MB |
| WebKit WebContent helper | 180 MB |
| Aggregate RSS | about 410 MB |

Settled idle after render:

| Metric | Result |
| --- | ---: |
| Tracked processes | 5 |
| Aggregate RSS | avg 410 MB |
| Aggregate CPU | avg 0.01%, max 0.20% |
| `footprint` physical memory | 171 MB dirty + 109 MB clean + 99 MB reclaimable |

The shell result is much smaller than launching an external Brave browser. Physical footprint is roughly **171 MB dirty** for the shell + Node + WebKit helper set, compared with Brave's roughly **853 MB** physical footprint for the same WebUI page. A direct kill of the shell process was also smoke-tested after adding parent-PID monitoring; the bundled Node child exited instead of remaining orphaned.

## Integrated Tauri WebUI shell

The repository now includes an integrated Tauri build option under `WebUI/src-tauri`. It launches the same Node WebUI backend, loads the local WebUI in Tauri's WebKit-backed webview, and emits startup metrics to stdout. Release builds are intended to behave like a non-developer installed app: WebUI assets, the example bundle, and a pinned official Node runtime are bundled into the `.app`; production code does not fall back to the source tree or Homebrew Node.

Build commands:

```bash
npm --prefix WebUI run tauri:build
make build-webui-tauri
```

`npm --prefix WebUI run tauri:build` runs `npm run tauri:prepare-node` first. That script downloads the pinned official Node release for the current macOS architecture, verifies it against Node's `SHASUMS256.txt`, and stages `node/bin/node` as a Tauri resource. The official Node binary links only against system libraries in the measured build.

Packaged footprint inputs:

| Item | Size |
| --- | ---: |
| `GUI for CLI WebUI.app` | 117.7 MB |
| Tauri executable | 9.0 MB |
| Bundled resources | 108.7 MB |
| Bundled Node runtime | 106.5 MB |

Launch metrics from the standalone bundled release app:

| Metric | Result |
| --- | ---: |
| App setup started | 103 ms |
| Node process started | 112 ms |
| Server `/api/manifest` ready | 246 ms |
| Window shown | 374 ms |
| Tauri/WebKit navigation finished | 487-496 ms |
| WebUI page JS rendered (`#app[data-state="ready"]`) | 237 ms inside the page |
| App process start to render notification | **727 ms** |

Process set after render:

| Process | RSS |
| --- | ---: |
| Tauri app | 93 MB |
| Bundled Node server | 61 MB |
| WebKit GPU helper | 44 MB |
| WebKit Networking helper | 23 MB |
| WebKit WebContent helper | 124 MB |
| Aggregate RSS | about 345 MB |

Settled idle after render:

| Metric | Result |
| --- | ---: |
| Tracked processes | 5 |
| Aggregate RSS | avg 345 MB |
| Aggregate CPU | avg 0.00%, max 0.20% |
| `footprint` physical memory | 152 MB dirty + 109 MB clean + 85 MB reclaimable |

The integrated standalone Tauri shell is close to the native WKWebView shell in memory footprint, larger on disk because of the Tauri executable/runtime, and a bit slower to the render notification in this run. It is still much lighter than launching a cold external Brave instance and similar in incremental physical memory to using an already-running Brave instance plus Node.
