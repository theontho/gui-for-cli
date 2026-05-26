---
output: 'platform-lessons.html'
title: 'Lessons from building GUI for CLI across desktop platforms'
description: 'What GUI for CLI learned from building, benchmarking, screenshot-rating, and shipping prototypes across SwiftUI, Tauri, Gio, Flutter, Slint, Raygui, ImGui, AppKit, Windows, browser, terminal, and other experimental frontends.'
eyebrow: 'Experiment lessons'
heading: 'The fastest prototype was not always the right product.'
lede: 'GUI for CLI tried many desktop and mobile UI stacks against one real bundle. The benchmark numbers mattered, but implementation difficulty, completeness, human visual-effectiveness ratings, accessibility, and packaging mattered just as much.'
actions: 'Experiment results|experiments.html|primary; Difficulty and visual report|https://github.com/theontho/gui-for-cli/blob/main/docs/ai/reports/platform-implementation-difficulty.md'
footer_title: 'Practical conclusion'
footer_text: 'Use native platform apps when the platform matters, Tauri when a reusable WebUI matters, and prototypes only after they prove complete workflow parity.'
---

::: section
::: wrap
## The benchmark changed the question

The first question was simple: which GUI toolkit starts fastest, uses the least memory, and packages smallest? The useful question became harder: which frontend can an AI actually implement completely, keep correct, package reliably, and make look like a real app while running the WGSExtract bundle?

That distinction matters. Several prototypes were impressive on narrow metrics. C++ ImGui, Rust ImGui, Iced, GTK4, egui, Makepad, Raygui, Slint, and Gio all produced fast or small results in at least one run. But the product-level workflow was not an empty window. It included setup scripts, long-running commands, terminal state, file and directory pickers, dynamic data sources, localized text, persisted config, row actions, platform packaging, and enough polish to be understood by a user.

The lesson is that runtime benchmarks are necessary but insufficient. The winning frontend is the one that combines acceptable speed with completeness, maintainability, platform integration, reliable packaging, and a screenshot that a human recognizes as the intended product.
:::
:::

::: section
::: wrap
## What the results said

| Platform family | What it proved | Visual result | Product conclusion |
| --- | --- | --- | --- |
| SwiftUI macOS | The original slow result was app startup work, not SwiftUI. After deferring bundle/workspace/config work, marker startup dropped into the low hundreds of milliseconds and the app stayed small and native. | Reference | Best primary Apple frontend. |
| Native Windows C# | The optimized Windows app had the best Windows process shape and startup/memory profile, especially NativeAOT. | Not in macOS screenshot pass | Best native Windows direction when Windows-specific polish matters. |
| WebUI reference | The TypeScript WebUI remained the easiest way to preserve complete behavior and visual polish. | Reference | Best behavior/UX baseline for WebUI-derived shells. |
| Browser, Tauri, Electron, and WKWebView shells | These are UX-equivalent for visual scoring because they render the same WebUI. Their differences are packaging, startup, memory, process lifecycle, update story, and platform integration. | Inherits WebUI | Tauri is the best portable packaged WebUI shell; browser is best for preview; WKWebView is the lean macOS shell; Electron is a comparison point. |
| TypeScript TUI and Textual-style terminals | Terminal UX is low-overhead and AI-friendly, but it is not a desktop GUI replacement. | 3/5 | Keep for automation and developer workflows. |
| Flutter | Strong cross-platform native-rendered promise and increasingly complete after a deep parity pass, but expensive to bring to spec and toolchain-heavy. | 4/5 | Promising research candidate, not a replacement until parity and packaging mature. |
| Gio | Small package and good startup, but full parity required a lot of custom runtime/UI behavior and still felt incomplete. | 2/5 | Useful lightweight research path; avoid promoting before deeper UX parity. |
| Slint | Excellent footprint/startup signals, but the full app shell took deep custom work and remained visibly incomplete in several areas. | 2/5 | Strong benchmark candidate, still research. |
| Raygui and ImGui | Very fast/small immediate-mode results, especially C/C++ variants, but accessibility, native affordances, and full workflow polish are hard. | 2/5 | Good renderer benchmarks; poor default product shells. |
| AppKit and ObjC AppKit | Native macOS APIs can be fast and small, but building full generic bundle UI by hand was fragile and layout-heavy. | 4/5 Swift, 2/5 ObjC | Useful native experiments; SwiftUI is the better Apple product path. |
| NodeGui and Dioxus WebUI | These proved useful comparison points, but package size, instrumentation gaps, and incomplete visual parity kept them from leading. | 1-2/5 | Research, not first choices. |
:::
:::

::: section
::: wrap
## Visual effectiveness closed the loop

The final human screenshot pass rated 34 regenerated screenshots from 1 to 5 for how effectively the AI implementation produced the intended interface. For conclusions, the visual model needs two normalizations: SwiftUI macOS and the WebUI are reference implementations, not experimental competitors, and Browser WebUI, Tauri, Electron, and WKWebView share one WebUI-shell UX score because they render the same interface.

After that normalization, the visual comparison is harsher: the comparable experimental set averages 2.55/5 with a median of 2. The only 5/5 experimental UX family is the WebUI shell family, and that is inherited from the WebUI reference rather than independently achieved by each shell. The 4/5 group is more instructive for rewrites: Flutter, Compose Desktop, Swift AppKit, and wxPython could produce recognizable, useful screens, but each carried implementation or packaging caveats.

Most custom toolkit rewrites clustered at 1-2/5. Gio, Slint, Raygui, ImGui, egui, Iced, Makepad, GPUI, Dioxus, GTK4, NodeGui, Avalonia, and Xilem/Vello may still be interesting benchmarks, but the visual pass said they did not yet communicate the full product as well as the reference UIs or the strongest rewrite candidates.

| Visual score | Surfaces | Lesson |
| ---: | --- | --- |
| Reference | SwiftUI macOS, WebUI | These anchor the comparison; they should not be counted as experimental wins. |
| 5 | WebUI shell family: Browser WebUI, Tauri, Electron, WKWebView shell | These inherit one UX result from the WebUI reference; choose among them by packaging, memory, startup, update, and platform integration. |
| 4 | Flutter, Compose Desktop, Swift AppKit, wxPython | Capable visuals, but the implementation story still had enough caveats to keep most of them experimental. |
| 3 | Android Compose, iOS SwiftUI Simulator, Fyne, Qt/QML, Python Textual, Tkinter, Toga, TypeScript TUI | Recognizable partial experiences; useful for comparison, demos, or narrower workflows. |
| 1-2 | Avalonia, NodeGui, Xilem/Vello, Gio, Slint, Raygui, ImGui, egui, Iced, Makepad, GPUI, Dioxus, GTK4, ObjC AppKit | The AI could open windows and render something, but product clarity and completeness were still missing. |
:::
:::

::: section
::: wrap
## Implementation difficulty mattered as much as speed

The local session history showed a clear pattern. Platforms that reused an existing complete rendering/runtime model were easier to make product-like. Platforms that forced the agent to recreate the whole bundle runtime, state model, data-source pipeline, command lifecycle, and layout system became long, multi-session efforts.

To avoid counting overnight or waiting time as implementation work, the session report now uses capped active time: time between adjacent session events is summed with a 30-minute maximum per gap. That changed the shape of the evidence. Flutter, Slint, Gio, Compose, AppKit, Raygui, and ImGui were still non-trivial, but some raw 20-hour wall-clock sessions were closer to 4-10 hours of active implementation. The biggest active-time buckets were not single renderers; they were benchmark/screenshot infrastructure, release/updater packaging, WGSExtract CLI/bundle integration, and the shared WebUI behavior model.

The hard implementations were not always the slowest apps. Flutter, Slint, Gio, AppKit, Raygui, C Raygui, and C++ ImGui all had attractive benchmark stories, but their session logs repeatedly show the same expensive gaps: config persistence, data-source refresh, setup execution, command cancellation, row actions, path pickers, terminal tabs, accessibility, RTL/localization, and packaging/CI issues.

The easiest path to a complete app was not "pick the fastest renderer." It was "reuse the most complete behavior model and only make the platform-specific shell native."
:::
:::

::: section
::: wrap
## Which platform makes sense when

| Situation | Best fit | Why |
| --- | --- | --- |
| Primary macOS app | SwiftUI macOS | Native integration, small package, good measured startup after app-specific deferral, strongest Apple maintainability. |
| Primary Windows app | Native Windows C# / NativeAOT | Fastest and simplest Windows process model in the Windows pass, with lower memory than WebView shells. |
| One portable desktop WebUI | Tauri WebUI | Reuses the complete TypeScript WebUI and gives a controlled packaged app without depending on a user browser; its UX score is inherited from the WebUI reference. |
| Development preview | WebUI server plus already-open browser | Fast enough when the browser is already open and easiest to debug. |
| Terminal-first or remote workflow | TypeScript TUI | Low overhead, scriptable, and does not pretend to be a desktop app. |
| Cross-platform native research | Flutter first, then Compose Desktop, Gio/Slint later | Flutter had the strongest complete-app push and a 4/5 visual result; Compose Desktop also looked strong, while Gio and Slint need deeper UX parity. |
| Tiny renderer benchmark | C++ ImGui, Rust/C Raygui, Rust ImGui | Best for learning footprint/startup limits, not for accessible native product UX. |
| Native macOS API comparison | Swift AppKit / ObjC AppKit | Useful controls for startup/package measurements, but more brittle than SwiftUI for full generic UI. |
| Browser-like fallback benchmark | Electron or Dioxus WebUI | Electron shares the WebUI UX but has worse package/memory tradeoffs; Dioxus remains less visually complete. |
:::
:::

::: section
::: wrap
## The practical rule

Start with the most complete product surface, not the fastest demo. For GUI for CLI today that means SwiftUI for Apple-native delivery and Tauri for packaged WebUI delivery. Keep the browser WebUI, WKWebView shell, and TUI as support surfaces. Keep the experimental platforms valuable by using them as measurement tools and design probes, not by promoting them before they match the same workflow.

The experiments were still worth doing. They exposed hidden startup work in the SwiftUI app, forced benchmark harnesses to measure real windows instead of headless shortcuts, clarified WebView and browser memory costs, and showed where AI-generated UI work becomes expensive. The visual ratings made the final lesson harder to ignore: product completeness is a benchmark too.
:::
:::
