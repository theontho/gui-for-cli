# macOS GUI toolkit benchmark run

This records the follow-up macOS benchmark pass for the native SwiftUI app and the Slint/Flutter research apps. The apps were built from the local worktree after the Flutter and Slint parity work and the SwiftUI startup optimization.

## Instrumented marker results

| Surface | Command/method | Size | Startup/readiness | Memory | Readiness definition |
| --- | --- | ---: | ---: | ---: | --- |
| SwiftUI macOS app | `make build-swift-release`, launched via LaunchServices with `--benchmark-output` | 9.2 MB `.app` | 852.8 ms median external wall-clock to first `WindowGroup.onAppear`; 518.1 ms median to `ContentView` initialized | Not resampled in this pass | First SwiftUI window appearance, plus an earlier content-initialization marker. |
| Slint macOS research app | `make build-slint-release`; `gui-for-cli-slint --bundle examples/WGSExtract --benchmark --once` | 12 MB release folder including sample bundle | 80.9 ms median internal UI-ready after warm cache | 30.0 MB median max RSS | Internal Slint component/UI readiness, not externally observed window-visible time. |
| Flutter macOS research app | Current equivalent: `make benchmark ARGS='flutter'` with Flutter 3.41.9 | 39.4 MB `.app` on disk; Flutter reports 41.2 MB | 223.0 ms median external wall-clock to bundle content-ready marker; 35.1 ms median from Dart `main` to content-ready | 112.8 MB median RSS at marker | App process launch until the localized bundle UI has been initialized and painted. |
| Raygui macOS research app | Current equivalent: `make benchmark ARGS='raygui'`; repeated direct `/usr/bin/time -l exp-platform/rust/raygui/target/release/gui-for-cli-raygui --bundle examples/WGSExtract --benchmark --once` samples | 2.3 MB release executable; 915 KB zipped app-only payload | 255.8 ms median content-ready marker; 278.9 ms median external process wall-clock | 90.9 MiB median max RSS; 92.8 MiB 2 s idle RSS | First native Raygui frame after bundle load and one immediate-mode render pass. |
| Gio macOS research app | PR #27 worktree `make build-gio-release`, direct executable launch with bundle env vars | 8.1 MB release folder including sample bundle; 6.4 MB stripped executable | 343.7 ms to first Gio frame in this smoke run | 186.7 MB RSS after a 2 s hold | First frame emitted by the Gio render loop after bundle load/window configuration. |
| React Native macOS research app | PR #24 worktree, `react-native-macos` 0.81.7 release Xcode build | 31.4 MB `.app`; 20.7 MB executable | 169.4 ms to native `applicationDidFinishLaunching` end marker | 95.6 MB RSS after a 2 s hold | Native app delegate/bridge setup marker, not yet a visual React-content readiness marker. |

## Visual sequential startup video check

For current user-perceived macOS startup comparisons, use this visual pass as the source of truth. It used `~/Desktop/rec.mp4`, recorded while launching the apps sequentially. The recording is variable-frame-rate-ish: `ffprobe` reports `r_frame_rate=120/1`, `avg_frame_rate=53940/977` (~55.2 fps), `time_base=1/600`, `duration=16.283333`, and `nb_frames=899`. Durations below therefore use actual per-frame timestamps (`best_effort_timestamp_time`) rather than frame count divided by a nominal FPS.

| Surface | Frame range | Absolute frame timestamps | Visual timing |
| --- | ---: | ---: | ---: |
| SwiftUI | 126-178 | 1.9117s -> 3.7417s | 1.830s start to fully rendered |
| Tauri | 250-296-331 | 4.4167s -> 5.0333s -> 5.4583s | 616.7 ms start to window; 1.042s start to fully rendered |
| Flutter | 430-519-522 | 6.9417s -> 7.9167s -> 7.9417s | 975.0 ms start to window; 1.000s start to fully rendered |
| Slint | 613-625 | 9.4833s -> 9.7750s | 291.7 ms start to fully rendered |

If those frame labels are interpreted as one-based editor frame numbers instead of zero-based frame indices, the only material change is SwiftUI at about 1.738s; Tauri, Flutter, and Slint remain effectively the same. This video check is useful for perceived startup comparison because it captures visible window/content presentation, but it is less repeatable than marker-based benchmarks because it depends on manual frame labeling, capture timing, display refresh, and app focus/window-manager behavior.

## Notes and caveats

- The video-derived visual timings are the current source of truth for perceived startup. Instrumented markers remain useful for profiling internal phases, but should not be compared as final startup times.
- SwiftUI and Flutter use explicit benchmark markers inside the apps, so their marker numbers are more specific to internal lifecycle points than the older window-polling/browser-render probes.
- Slint also has an internal UI-ready benchmark. It is valuable as a low-footprint renderer signal, but the visual video timing is the comparable startup number.
- Raygui's marker comes from the app's `--benchmark --once` mode and is directly comparable to other instrumented first-frame/content-ready markers, not to the visual video timing table. The staged release folder was 4.5 GB because it copied the full WGSExtract sample bundle; the app-only binary payload is the meaningful Raygui runtime size.
- Flutter's generated macOS sandbox is disabled by the research build target so the app can read the local bundle path and write the benchmark marker.
- SwiftUI improved because launch no longer reloads the default localization bundle unnecessarily and no longer recopies an unchanged demo bundle workspace on every launch.
- Gio and React Native were benchmarked from PR worktrees under `~/src/gui-worktree` after moving their branch-specific app work out of the main benchmark/docs checkout.
- The React Native number is a native lifecycle marker only. It confirms the generated macOS runner starts quickly, but it should not be ranked against the VFR video visual startup numbers until a React-content/rendered marker or a video pass is captured.
- The visual video check highlights user-perceived presentation differences: Slint appeared fastest visually, Flutter and Tauri were around one second to rendered content, and SwiftUI appeared slower in this recording than its internal marker suggested.

## Interpretation

SwiftUI remains the smallest and most platform-integrated macOS app, but the current visual startup source of truth shows it fully rendered in 1.83s in this capture. Flutter is the strongest cross-platform native-rendered research candidate after the parity work: it is larger and higher-RSS than SwiftUI, but reached fully rendered content in 1.00s and now exercises data sources, setup UI, actions, path picking, and command rendering. Slint remains the footprint and visual-startup winner at 291.7 ms, but its app shell is still less complete than SwiftUI and Flutter. Raygui is now the smallest app-only native GUI payload at 2.3 MB uncompressed and 915 KB zipped, with a 255.8 ms median content-ready marker and one-process runtime, but it needs the same visual startup capture before comparing perceived startup against Slint or Flutter. Gio is very small on disk and gets a real first-frame metric, but the first smoke run showed higher RSS than expected and needs more parity/visual testing. React Native macOS produced a compact app bundle and quick native lifecycle marker, but still needs a visual/rendered-content benchmark before it can be compared fairly.
