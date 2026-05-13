# New ImGui renderer benchmarks

Benchmarked on **2026-05-12 15:37 PDT** on **macOS 26.4.1 (25E253)**, **Apple M1 Pro**, **10 logical CPU cores**, **32 GB RAM**.

This pass compares the Rust Dear ImGui renderer and the new C++ Dear ImGui renderer after the font/section polish and C++ parity fills. Both staged release folders include the executable, `examples/WGSExtract`, and built-in strings.

## Summary

| Metric | Rust ImGui | C++ ImGui |
| --- | ---: | ---: |
| Staged release size | 5.4 MB | 3.1 MB |
| Executable size | 3.6 MB | 1.3 MB |
| Built-in strings payload | 268 KB | 268 KB |
| Samples | 7 | 7 |
| Bundle loaded median | 16.8 ms | 2.596 ms |
| Bundle loaded range | 16.2-26.3 ms | 2.551-2.633 ms |
| Internal UI-ready median | 17.0 ms | 2.613 ms |
| Internal UI-ready range | 16.3-27.9 ms | 2.567-2.655 ms |
| Full feature warm median | 636.4 ms | 252.461 ms |
| Full feature warm range | 607.2-959.3 ms | 241.398-281.390 ms |
| One-shot max RSS | 28.9 MiB | 29.2 MiB |
| Live app RSS after about 2 seconds | 89.4 MiB | 90.5 MiB |
| Data sources declared | 5 | 5 |
| Data source cache entries loaded | 12 | 4 |

The C++ executable is about **2.8x smaller** than the Rust executable in this build, and the staged C++ release folder is about **2.3 MB smaller**. One-shot benchmark RSS is now roughly equivalent after moving C++ data-source execution off the immediate render path, while live window RSS remains close because both renderers pay for an OpenGL/ImGui desktop window.

The `data_sources_loaded` numbers are not perfectly equivalent yet: Rust reports cache entries from its shared Rust data-source/control-text pipeline, while C++ reports native C++ data-source control cache entries.

## LOC / KLOC

| Area | LOC | KLOC | Notes |
| --- | ---: | ---: | --- |
| Rust ImGui renderer-local source | 1,689 | 1.69 | `exp-platform/rust/imgui/src/*.rs` only. |
| Shared Rust GUI logic | 3,817 | 3.82 | `exp-platform/rust/shared/src/*.rs`, used by Rust ImGui and Slint. |
| Rust ImGui including shared Rust logic | 5,506 | 5.51 | Renderer-local Rust plus shared Rust logic. |
| C++ ImGui source | 2,819 | 2.82 | `exp-platform/cpp/imgui-cpp/src/*.cpp` and `*.hpp`. |
| C++ ImGui CMake | 79 | 0.08 | `exp-platform/cpp/imgui-cpp/CMakeLists.txt`. |
| C++ ImGui including CMake | 2,898 | 2.90 | Native C++ port plus build file. |

## Command log

```sh
make build-imgui-release
make build-imgui-cpp-release

du -sh out/release/imgui \
  out/release/imgui-cpp \
  exp-platform/rust/imgui/target/release/gui-for-cli-imgui \
  exp-platform/cpp/imgui-cpp/build/gui-for-cli-imgui-cpp \
  out/release/imgui/resources/BuiltinStrings \
  out/release/imgui-cpp/resources/BuiltinStrings

for i in 1 2 3 4 5 6 7; do
  GUI_FOR_CLI_OFFLINE=1 exp-platform/rust/imgui/target/release/gui-for-cli-imgui \
    --bundle examples/WGSExtract \
    --benchmark \
    --benchmark-full \
    --once
done

for i in 1 2 3 4 5 6 7; do
  GUI_FOR_CLI_OFFLINE=1 exp-platform/cpp/imgui-cpp/build/gui-for-cli-imgui-cpp \
    --bundle examples/WGSExtract \
    --repo-root "$(pwd)" \
    --benchmark \
    --benchmark-full \
    --once
done

GUI_FOR_CLI_OFFLINE=1 /usr/bin/time -l exp-platform/rust/imgui/target/release/gui-for-cli-imgui \
  --bundle examples/WGSExtract \
  --benchmark \
  --benchmark-full \
  --once

GUI_FOR_CLI_OFFLINE=1 /usr/bin/time -l exp-platform/cpp/imgui-cpp/build/gui-for-cli-imgui-cpp \
  --bundle examples/WGSExtract \
  --repo-root "$(pwd)" \
  --benchmark \
  --benchmark-full \
  --once
```

## Raw samples

### Rust ImGui

| Sample | Bundle loaded | UI ready | Full feature warm |
| ---: | ---: | ---: | ---: |
| 1 | 26.3 ms | 27.9 ms | 959.3 ms |
| 2 | 16.8 ms | 17.0 ms | 622.0 ms |
| 3 | 16.2 ms | 16.3 ms | 706.5 ms |
| 4 | 17.0 ms | 17.1 ms | 636.4 ms |
| 5 | 17.2 ms | 17.4 ms | 627.2 ms |
| 6 | 16.8 ms | 16.9 ms | 607.2 ms |
| 7 | 16.6 ms | 16.6 ms | 660.9 ms |

`/usr/bin/time -l` one-shot max RSS: **30,343,168 bytes** (**28.9 MiB**).

### C++ ImGui

| Sample | Bundle loaded | UI ready | Full feature warm |
| ---: | ---: | ---: | ---: |
| 1 | 2.617 ms | 2.633 ms | 270.546 ms |
| 2 | 2.587 ms | 2.604 ms | 278.653 ms |
| 3 | 2.633 ms | 2.655 ms | 281.390 ms |
| 4 | 2.551 ms | 2.567 ms | 241.398 ms |
| 5 | 2.608 ms | 2.624 ms | 246.508 ms |
| 6 | 2.561 ms | 2.578 ms | 241.481 ms |
| 7 | 2.596 ms | 2.613 ms | 252.461 ms |

`/usr/bin/time -l` one-shot max RSS: **30,638,080 bytes** (**29.2 MiB**).

## Notes

- C++ Dear ImGui is built with `IMGUI_DISABLE_DEMO_WINDOWS` and `IMGUI_DISABLE_DEBUG_TOOLS`.
- C++ Dear ImGui loads the default ImGui font at 17 px and a section font at 21 px, then uses `SeparatorText()` for section headings.
- C++ Dear ImGui now includes terminal close/cancel controls, visible command status labels, destructive action styling, setup/action running-state disabling, macOS path picker buttons, and RTL sidebar placement.
- C++ data-source scripts now load asynchronously during normal rendering; the `--benchmark-full` path waits for those async loads to finish so the warm marker still measures populated data controls.
- Rust Dear ImGui loads larger default fonts and uses a larger section font plus separators because the Rust `imgui` binding in this checkout does not expose `SeparatorText()`.
- These are internal benchmark markers, not external visual first-window timings. They are useful for footprint and warm-path comparison, but should not be mixed directly with rendered-content startup measurements without a visual startup pass.
