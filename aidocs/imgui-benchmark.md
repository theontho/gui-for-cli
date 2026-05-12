# Dear ImGui renderer benchmark

Benchmarked on **2026-05-12 13:10 PDT** from the local `imgui-renderer-benchmark` branch after adding the Rust Dear ImGui desktop renderer and parity fixes.

## Results

| Metric | Result |
| --- | ---: |
| Staged release size | 5.3 MB |
| Executable size | 3.6 MB |
| Built-in strings payload | 240 KB |
| Samples | 7 |
| Bundle loaded median | 19.7 ms |
| Bundle loaded range | 18.3-24.5 ms |
| Internal UI-ready median | 19.8 ms |
| Internal UI-ready range | 18.4-24.6 ms |
| Full feature warm median | 766.3 ms |
| Full feature warm range | 524.0-844.9 ms |
| One-shot max RSS | 29.2 MB |
| Live app RSS after about 2 seconds | 91.3 MB |
| Live sampled CPU | 6.5% |

The staged release size is `out/release/imgui` after `make build-imgui-release`. It includes the `gui-for-cli-imgui` executable, `Examples/WGSExtract`, and `Sources/GUIForCLICore/Resources/BuiltinStrings`.

## Command log

```sh
make build-imgui-release
du -sh out/release/imgui
du -sh Apps/ImGui/target/release/gui-for-cli-imgui
du -sh out/release/imgui/Sources/GUIForCLICore/Resources/BuiltinStrings

for i in 1 2 3 4 5 6 7; do
  GUI_FOR_CLI_OFFLINE=1 Apps/ImGui/target/release/gui-for-cli-imgui \
    --bundle Examples/WGSExtract \
    --benchmark \
    --benchmark-full \
    --once
done

/usr/bin/time -l Apps/ImGui/target/release/gui-for-cli-imgui \
  --bundle Examples/WGSExtract \
  --benchmark \
  --benchmark-full \
  --once
```

Raw samples:

| Sample | Bundle loaded | UI ready | Full feature warm |
| ---: | ---: | ---: | ---: |
| 1 | 24.5 ms | 24.6 ms | 613.8 ms |
| 2 | 19.7 ms | 19.8 ms | 614.2 ms |
| 3 | 18.3 ms | 18.4 ms | 524.0 ms |
| 4 | 20.9 ms | 21.0 ms | 844.9 ms |
| 5 | 18.7 ms | 18.9 ms | 783.1 ms |
| 6 | 19.1 ms | 19.3 ms | 836.0 ms |
| 7 | 21.9 ms | 22.0 ms | 766.3 ms |

## Interpretation

The Dear ImGui renderer is the smallest staged desktop renderer currently measured in this repo: **5.3 MB** including the sample bundle and built-in strings. Its internal startup marker is also very fast at **19.8 ms median UI-ready**, and its one-shot benchmark max RSS is **29.2 MB**.

The main caveat is comparability. `ui_ready_ms` is an internal app readiness marker emitted by `--benchmark --once`; it is not an external visual first-window or rendered-content measurement like the video-derived macOS timings in `gui-toolkit-macos-benchmark-run.md`. The live app RSS sample is higher than the one-shot benchmark max RSS because it measures the OpenGL/winit/ImGui window running for about two seconds.

Use the ImGui number as a strong footprint/internal-startup signal, but capture an external visual startup pass before ranking it against SwiftUI, Slint, Flutter, or WebView shells for user-perceived launch speed.
