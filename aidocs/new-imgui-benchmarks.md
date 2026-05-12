# New ImGui renderer benchmarks

Benchmarked on **2026-05-12 14:42 PDT** on **macOS 26.4.1 (25E253)**, **Apple M1 Pro**, **10 logical CPU cores**, **32 GB RAM**.

This pass compares the Rust Dear ImGui renderer and the new C++ Dear ImGui renderer after the font/section polish and C++ parity fills. Both staged release folders include the executable, `Examples/WGSExtract`, and built-in strings.

## Summary

| Metric | Rust ImGui | C++ ImGui |
| --- | ---: | ---: |
| Staged release size | 5.4 MB | 3.1 MB |
| Executable size | 3.6 MB | 1.3 MB |
| Built-in strings payload | 268 KB | 268 KB |
| Samples | 7 | 7 |
| Bundle loaded median | 16.1 ms | 2.523 ms |
| Bundle loaded range | 15.0-21.8 ms | 2.467-2.783 ms |
| Internal UI-ready median | 16.2 ms | 2.538 ms |
| Internal UI-ready range | 15.1-22.2 ms | 2.482-2.798 ms |
| Full feature warm median | 572.3 ms | 17.623 ms |
| Full feature warm range | 532.0-614.9 ms | 17.377-18.388 ms |
| One-shot max RSS | 28.8 MiB | 10.0 MiB |
| Live app RSS after about 2 seconds | 89.0 MiB | 86.4 MiB |
| Data sources declared | 5 | 5 |
| Data source cache entries loaded | 12 | 4 |

The C++ executable is about **2.8x smaller** than the Rust executable in this build, and the staged C++ release folder is about **2.3 MB smaller**. The one-shot benchmark RSS is also much lower for C++, while live window RSS is close because both renderers pay for an OpenGL/ImGui desktop window.

The `data_sources_loaded` numbers are not perfectly equivalent yet: Rust reports cache entries from its shared Rust data-source/control-text pipeline, while C++ reports native C++ data-source control cache entries.

## LOC / KLOC

| Area | LOC | KLOC | Notes |
| --- | ---: | ---: | --- |
| Rust ImGui renderer-local source | 1,689 | 1.69 | `Apps/ImGui/src/*.rs` only. |
| Shared Rust GUI logic | 3,817 | 3.82 | `Apps/RustShared/src/*.rs`, used by Rust ImGui and Slint. |
| Rust ImGui including shared Rust logic | 5,506 | 5.51 | Renderer-local Rust plus shared Rust logic. |
| C++ ImGui source | 2,744 | 2.74 | `Apps/ImGuiCpp/src/*.cpp` and `*.hpp`. |
| C++ ImGui CMake | 78 | 0.08 | `Apps/ImGuiCpp/CMakeLists.txt`. |
| C++ ImGui including CMake | 2,822 | 2.82 | Native C++ port plus build file. |

## Command log

```sh
make build-imgui-release
make build-imgui-cpp-release

du -sh out/release/imgui \
  out/release/imgui-cpp \
  Apps/ImGui/target/release/gui-for-cli-imgui \
  Apps/ImGuiCpp/build/gui-for-cli-imgui-cpp \
  out/release/imgui/Sources/GUIForCLICore/Resources/BuiltinStrings \
  out/release/imgui-cpp/Sources/GUIForCLICore/Resources/BuiltinStrings

for i in 1 2 3 4 5 6 7; do
  GUI_FOR_CLI_OFFLINE=1 Apps/ImGui/target/release/gui-for-cli-imgui \
    --bundle Examples/WGSExtract \
    --benchmark \
    --benchmark-full \
    --once
done

for i in 1 2 3 4 5 6 7; do
  GUI_FOR_CLI_OFFLINE=1 Apps/ImGuiCpp/build/gui-for-cli-imgui-cpp \
    --bundle Examples/WGSExtract \
    --repo-root "$(pwd)" \
    --benchmark \
    --benchmark-full \
    --once
done

/usr/bin/time -l Apps/ImGui/target/release/gui-for-cli-imgui \
  --bundle Examples/WGSExtract \
  --benchmark \
  --benchmark-full \
  --once

/usr/bin/time -l Apps/ImGuiCpp/build/gui-for-cli-imgui-cpp \
  --bundle Examples/WGSExtract \
  --repo-root "$(pwd)" \
  --benchmark \
  --benchmark-full \
  --once
```

## Raw samples

### Rust ImGui

| Sample | Bundle loaded | UI ready | Full feature warm |
| ---: | ---: | ---: | ---: |
| 1 | 21.8 ms | 22.2 ms | 532.0 ms |
| 2 | 15.0 ms | 15.1 ms | 614.9 ms |
| 3 | 16.4 ms | 16.6 ms | 583.4 ms |
| 4 | 17.2 ms | 17.4 ms | 562.2 ms |
| 5 | 16.1 ms | 16.2 ms | 580.0 ms |
| 6 | 16.0 ms | 16.1 ms | 572.3 ms |
| 7 | 16.1 ms | 16.2 ms | 565.4 ms |

`/usr/bin/time -l` one-shot max RSS: **30,195,712 bytes** (**28.8 MiB**).

### C++ ImGui

| Sample | Bundle loaded | UI ready | Full feature warm |
| ---: | ---: | ---: | ---: |
| 1 | 2.783 ms | 2.798 ms | 18.067 ms |
| 2 | 2.533 ms | 2.549 ms | 17.623 ms |
| 3 | 2.484 ms | 2.498 ms | 17.404 ms |
| 4 | 2.596 ms | 2.611 ms | 18.388 ms |
| 5 | 2.523 ms | 2.538 ms | 17.377 ms |
| 6 | 2.508 ms | 2.522 ms | 17.939 ms |
| 7 | 2.467 ms | 2.482 ms | 17.592 ms |

`/usr/bin/time -l` one-shot max RSS: **10,452,992 bytes** (**10.0 MiB**).

## Notes

- C++ Dear ImGui is built with `IMGUI_DISABLE_DEMO_WINDOWS` and `IMGUI_DISABLE_DEBUG_TOOLS`.
- C++ Dear ImGui loads the default ImGui font at 17 px and a section font at 21 px, then uses `SeparatorText()` for section headings.
- C++ Dear ImGui now includes terminal close/cancel controls, visible command status labels, destructive action styling, setup/action running-state disabling, macOS path picker buttons, and RTL sidebar placement.
- Rust Dear ImGui loads larger default fonts and uses a larger section font plus separators because the Rust `imgui` binding in this checkout does not expose `SeparatorText()`.
- These are internal benchmark markers, not external visual first-window timings. They are useful for footprint and warm-path comparison, but should not be mixed directly with rendered-content startup measurements without a visual startup pass.
