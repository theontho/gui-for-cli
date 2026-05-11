# Agent history behavior spec

This document captures the recurring implementation behaviors that agents working on GUI for CLI have needed to be reminded to preserve. It is a checklist for future app, renderer, and bundle work.

## Required behavior

1. **Keep surfaces at feature parity.** Experimental renderers must not stop at a visually similar shell. They need the same bundle schema coverage, settings/config editing, setup flow, data-source refresh, action confirmation/precheck behavior, library tables, preferences, and terminal/process behavior as the SwiftUI and WebUI implementations.
2. **Respect bundle/workspace semantics.** Treat the bundle root/workspace as the source for manifests, pages, strings, setup scripts, generated config, reference data, and per-bundle `state.json`. Do not silently fall back to unrelated paths or hide failed reads/writes.
3. **Handle terminal/process lifecycle explicitly.** Every user action or setup run should create visible terminal output, preserve command/status context, stream stdout/stderr, expose running/finished/failed/cancelled state, and avoid duplicate process starts when a command is already running.
4. **Persist user-facing state.** Selected page, locale, icon set, color theme, config paths, field values, checkbox selections, and setup results should survive app restarts using the same bundle-state model.
5. **Honor localization, RTL, and accessibility.** Localized strings must flow through the app, RTL locales/terminal text direction must render correctly, and custom controls must have usable labels, hints, and roles for accessibility.
6. **Avoid legacy fallback paths.** This project is still greenfield. When a schema, state model, or behavior changes, update all call sites instead of adding compatibility branches that keep old behavior alive.
7. **Avoid megafiles.** Split new functionality into focused files before files exceed roughly 500 lines.
8. **Validate realistic behavior.** Run the relevant tests/builds/benchmarks for the surface being changed. For experimental apps, benchmark the full-featured renderer, not a thin placeholder.

## Flutter PR checklist

- The Flutter app should load the same WGS Extract bundle schema as SwiftUI/WebUI, including setup, config files, data sources, action conditions, confirmations, prechecks, and library rows.
- It should provide full app-shell behavior: sidebar grouping, settings page, standard options, setup status, terminal tabs, process cancellation/close, command status, path picking, workspace opening, and benchmark markers.
- It should parse `terminalTextDirection`, apply RTL-aware layout for RTL locales, expose explicit semantics around custom shell widgets, and keep all Dart files below the megafile threshold.
