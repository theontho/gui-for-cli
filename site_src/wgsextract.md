---
output: 'wgsextract.html'
title: 'WGSExtract and GUI for CLI'
description: 'How WGSExtract became the first real app developed with GUI for CLI.'
eyebrow: 'First real app'
heading: 'WGSExtract made GUI for CLI prove itself.'
lede: 'The WGSExtract bundle is the first real application built through GUI for CLI. It pushed the project beyond demo controls into setup, command execution, data state, localization, and packaged releases.'
actions: 'Open frontends|frontends.html; See experiments|experiments.html'
footer_title: 'WGSExtract'
footer_text: 'A real workflow drove the generic app shell.'
---

::: section
::: wrap
::: section-head
## Why this bundle mattered

WGSExtract gave GUI for CLI a real target: a genomics workflow with long-running tools, user-selected files, setup state, reference data, and packaging expectations.
:::

::: grid three
::: card
{{ kicker: Setup }}
### More than a launch button
The bundle needs setup steps, environment checks, external scripts, tool paths, and recoverable state before actions are safe to run.
:::

::: card
{{ kicker: Commands }}
### Long-running process UX
Genome commands need terminal output, cancellation, exit code handling, path arguments, generated command previews, and clear disabled states.
:::

::: card
{{ kicker: Data }}
### Dynamic rows and config
WGSExtract exercises data sources, state-dependent actions, persisted settings, localization, icons, and workspace files.
:::
:::
:::
:::

::: section
::: wrap
## What it forced into the platform

- bundle loading from folders and archives;
- `manifest.json` and page schema validation;
- setup dry-runs and setup execution;
- dynamic page controls and action state;
- terminal output panes and process lifecycle handling;
- config storage in platform-standard Application Support paths;
- localized strings and semantic icon maps;
- bundle-specific packaging and app identity.

Those requirements are generic. The WGSExtract app is concrete, but the runtime behavior belongs to GUI for CLI so another CLI tool can reuse the same shell.
:::
:::

::: section
::: wrap
## Why it shaped the frontend decision

A toy bundle can make any renderer look good. WGSExtract made the comparison harder: the frontend had to carry real commands, real setup, and real release packaging. `swiftui-macos` and `tauri-webui` are the two surfaces that currently balance completeness, maintainability, and product packaging.
:::
:::
