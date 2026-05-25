---
output: 'frontends.html'
title: 'GUI for CLI frontends'
description: 'The two GUI for CLI product frontends are SwiftUI macOS and Tauri WebUI.'
eyebrow: 'Product frontends'
heading: 'Two frontends: swiftui-macos and tauri-webui.'
lede: 'The renderer experiments were useful, but the product surface is intentionally small: one native Apple app and one packaged WebUI app.'
actions: 'Open experiments|experiments.html; View docs|docs.html'
footer_title: 'Product split'
footer_text: 'Keep reusable behavior in the core, and keep frontend-specific behavior in the app shell.'
---

::: section
::: wrap
::: grid two
::: card
{{ kicker: Native Apple }}
### `swiftui-macos`
The SwiftUI app is the primary native macOS frontend. It uses shared Swift code for bundle loading, setup state, localization, configuration, command rendering, and process execution.

```bash
make run PLATFORM=swiftui-macos BUNDLE=examples/WGSExtract
make package PLATFORM=swift
```
:::

::: card
{{ kicker: Portable WebUI }}
### `tauri-webui`
The Tauri app packages the TypeScript WebUI and local Node backend as a desktop app. It is the product WebUI shell for cross-platform distribution.

```bash
make run PLATFORM=tauri BUNDLE=examples/WGSExtract
make package PLATFORM=tauri
```
:::
:::
:::
:::

::: section
::: wrap
## Supporting surfaces are not product frontends

| Surface | Role |
| --- | --- |
| Swift CLI | Bundle inspection, setup, config, and command execution support. |
| TypeScript Web UI server/client | Implementation layer reused by Tauri and useful for development preview. |
| TypeScript shared runtime | Model, localization, rendering, and utility code shared by web-based surfaces. |
| TypeScript TUI | Terminal-first development and automation path, not a desktop GUI frontend. |

The stable product question is narrower than "what code can run?" The two frontends users should think about are `swiftui-macos` and `tauri-webui`.
:::
:::

::: section
::: wrap
## Design rule

Reusable business logic belongs in `GUIForCLICore` or the shared TypeScript runtime. Presentation, platform integrations, packaging, and native affordances belong in one of the two product frontend shells. Prototype renderers should not add compatibility shims or product claims until they can run the same WGSExtract workflow.
:::
:::
