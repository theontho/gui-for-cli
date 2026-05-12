# Agent History Timeline and Behavior Spec

This document distills the recoverable Copilot CLI history for `gui-for-cli` into an agent handoff spec. It is meant to be read before implementing new GUI surfaces, parity ports, benchmarks, or refactors.

## Sources and limits

- Primary source: Copilot CLI session store and local Copilot session event logs for `gui-for-cli`, `gui-for-cli2`, `gui-for-cli3`, related worktrees, and tightly related `wgsextract-cli` handoff sessions.
- VS Code workspace storage was checked for `~/src/gui-for-cli` and `~/src/gui-for-cli2`. The recoverable records only contained empty chat session indexes and custom agent mode state, not message transcripts.
- The timeline below includes all recoverable matching sessions and the count of user turns in each session. It summarizes turn content by session rather than duplicating every long raw message, stack trace, and skill context block.

## Behavior spec agents should implement and not forget

### Product contract

1. `gui-for-cli` is a generic toolkit for rendering GUI/TUI/WebUI front ends for CLI tools from portable bundle manifests. WGS Extract is the first concrete user, but new functionality must be generic and reusable by other bundles.
2. The canonical contract is the bundle format and platform-neutral runtime behavior, not any one UI implementation. SwiftUI, WebUI, TUI, Tauri, Windows, and benchmark ports must preserve the same semantics.
3. The WebUI shared TypeScript logic is an important behavioral reference for cross-platform ports. Do not ignore it when implementing Windows, Tauri, TUI, or alternative app stacks.
4. The repo is still greenfield. Do not add compatibility shims, legacy fallbacks, duplicate old formats, or deprecation paths. If a schema or file layout changes, update every caller, test, example, and doc in the same change.

### Bundle format and loading

1. Bundles may be directories or archives. They contain a `manifest.json`, page JSON files under `pages/`, string tables under `strings/`, scripts/assets, optional icons/favicons, and workspace/config assets.
2. `manifest.json` should remain small enough to describe bundle metadata, setup, locale/defaults, page order, terminal behavior, exit code overrides, icon options, and workspace/config behavior. Page details belong in separate page JSON files.
3. The schema and examples are part of the product. Update `docs/schema`, `Examples/WGSExtract`, generated demo manifests, Swift models, TypeScript models, WebUI tests, and docs together.
4. Built-in app strings are not bundle strings. Keep them in app-owned resources so bundle authors only provide bundle-specific strings.
5. A missing GUI string should render the key so missing localization is obvious. Do not silently fall back to English for bundle strings in a way that hides missing translations.

### Workspace, setup, config, and state

1. Persist a bundle workspace. Pixi installs, generated config, downloaded library state, and similar bundle-local artifacts should survive app relaunches.
2. Setup/bootstrap can be script-driven. Setup scripts receive bundle/workspace context, can create default configs, and may choose bundle-local, user config, or platform app-support locations when the manifest allows it.
3. For WGS Extract, Pixi dependencies must actually be installed with `pixi install` before dependency checks are trusted.
4. Settings/config files may live inside the bundle workspace. Config editors should load on startup or after the user chooses a valid path, save automatically on setting changes, and avoid permanent save/load button rows unless a typed path needs a temporary explicit load action.
5. Non-config UI state should be portable JSON in the bundle workspace, not `UserDefaults`, unless it is truly app preference state.
6. File and directory choosers should open near the current valid path. If the current value is a valid file or directory path, or a path whose parent directory exists, start the picker there.

### Commands and terminal behavior

1. Actions execute real commands, not simulations. Audit command names, flags, required fields, and labels against current CLI help before shipping.
2. Action buttons must be disabled until every required placeholder/variable is defined. Disabled reasons should be useful, localized, and not generic placeholder leaks like "fill in row.ref".
3. Every launched action gets a terminal tab. The main/general tab is never dismissible; generated tabs have a close/cancel affordance.
4. While an action runs, its button and tab show a spinner/running state. Closing a running tab cancels/kills that command.
5. Killing the WebUI server or app must also kill any child CLI process tree. No dangling CLI processes.
6. Terminal output should auto-scroll while new logs arrive unless the user intentionally scrolls away.
7. Failed or warning exit statuses should be visible on the tab with color/status icon, and clicking or focusing the status should explain the exit code.
8. Exit code explanations have generic app defaults, can be overridden by the manifest, and are localized through string tables.
9. The terminal drawer should start around 20-25% of the window, live at the bottom, be smoothly resizable, have a hide/show icon button at bottom right, and avoid janky resizer behavior.
10. Terminal text, logs, command output, and path fields stay LTR in RTL UI unless a manifest setting explicitly changes terminal direction.

### Dynamic controls and data sources

1. Dynamic controls must be generic. Do not hard-code WGS Extract data into app code.
2. `libraryList` style controls are hydrated from data sources/scripts. Rows can define columns, tags/pills, status-aware actions, row placeholders, and per-row action visibility/enabled conditions.
3. Script-driven dropdowns should represent actual available choices. For WGS reference genome fields, show downloaded genomes where the workflow requires downloaded genomes.
4. Pages with state/data scripts should refresh after an action finishes so library state, downloaded assets, generated files, and button visibility update immediately.
5. Never show fake placeholder row data while loading. Use loading, empty, and error states.
6. State-based buttons should keep stable positions where possible. Example: installed rows show delete/unindex/unsort actions; not-installed rows show download/sort/index actions; unavailable actions are hidden or disabled according to manifest semantics.
7. Destructive actions use native destructive styling: red role/text/button treatment on macOS and equivalent platform conventions elsewhere.

### WGS Extract bundle requirements that tend to be missed

1. WGS Extract is the first customer and should be used to find missing generic platform behavior, but product features must still be generic.
2. Compare every WGS action against current WGS CLI help. Avoid stale aliases like `wgse` if the CLI uses another command path.
3. Reference genome data should come from source CSV/scripts or CLI-accessible data, not duplicated app code. Do not copy full reference genomes into the repo except small dedicated test fixtures.
4. Library page behavior includes downloaded/recommended/source/build tags, state-specific action visibility, refresh after download/delete/bootstrap, and no redundant text when a column/tag already conveys it.
5. Realign is a distinct flow/section. It needs its own input BAM, a downloaded reference genome dropdown for the new target reference, a visible realign button, and visible disk/resource estimates before work starts.
6. Long-running work that can fail from disk/resource constraints should check and display required resources before starting.
7. Page naming and grouping matter: keep conversion and analysis workflows organized; avoid arbitrary old page groupings when the WGS workflow indicates a clearer split.

### UI/UX and platform parity

1. Do not faithfully reproduce rough mockup styling. Use platform-native defaults first: Apple-native controls on macOS/iOS, Fluent/WinUI conventions on Windows, and polished but lightweight web/TUI conventions elsewhere.
2. Default action buttons are system-default, usually gray. The blue in early mockups meant "default system button", not custom blue styling. Red is reserved for destructive actions.
3. Pages should use available width instead of narrow arbitrary max widths.
4. Sidebars need stable icon widths so labels align. Page/sidebar icons can be image, emoji, SF Symbol, Bootstrap Icon, or hidden according to platform and manifest settings.
5. Settings and library can be bottom/sidebar pages. Page order and sidebar sections are part of the user experience, not incidental.
6. Tooltips must be useful, fast, localized, and container-aware. They should not overflow behind sidebars or window edges. Clicking labels with info should show the same info as the info button.
7. The bundle summary belongs beside the title as an info affordance, not as a truncated paragraph that hides meaning.
8. Support dynamic font size. On macOS, `Cmd+Plus` and `Cmd+Minus` should adjust generated UI text size where feasible.
9. WebUI mobile layout should not preserve a vertical desktop sidebar that consumes the viewport. Navigation should wrap horizontally, avoid broken overflow, and top bars should not stay sticky if that makes the small layout worse.
10. WebUI favicon/title should come from the bundle where available.
11. TUI should be a real full-screen interactive UI: colored, readable in light and dark terminals, responsive to terminal resize, scrollable internal panes, keyboard focus switching, path autocomplete, pane resizing, terminal tabs, cancellation, and clean `q` exit.

### Localization, RTL, and accessibility

1. Every visible app and bundle string must be localizable. Lint for missing keys and suspicious unchanged non-English values.
2. Locale detection should follow system locale at startup, with a user-visible language setting.
3. RTL locales should mirror layout using leading/trailing semantics. Sidebar moves to the right; hide buttons and play icons mirror when appropriate.
4. Path fields and terminal/log output remain LTR in RTL interfaces unless explicitly configured otherwise.
5. SwiftUI and WebUI should have equivalent RTL behavior. Do not fix RTL in one surface and leave the other inconsistent.
6. Accessibility annotations should be generated from manifest labels, help text, tooltips, and control semantics wherever possible.
7. Icon-only controls require labels. Resizers, tab close buttons, info buttons, nav items, dialogs, form rows, and generated controls need keyboard/focus/AX coverage.
8. Use macOS AX smoke tests and axe/web accessibility checks after UI changes. Missing labels and focus traps are product bugs, not polish.

### Performance and benchmarking

1. Startup performance is measured to first real render of usable UI, not process spawn alone.
2. SwiftUI startup improved from roughly 1.8s to about 0.7s; use those lessons for WebUI, Tauri, and TypeScript TUI.
3. Avoid heavy synchronous work before first render. Defer setup checks, expensive data-source refreshes, large localization passes, and noncritical process work until after initial UI appears.
4. Benchmarks should report startup, idle CPU, memory footprint, app/package size, and whether runtime/framework payloads are app-specific or shared system/runtime cost.
5. Compare packaging routes fairly: native app payload, self-contained package, bootstrap installer, already-open browser route, cold browser route, Tauri, Electron, WKWebView, TUI, and native platform ports.

### Code organization and agent workflow

1. No megafiles. Files over roughly 500 lines need active scrutiny. Split obvious classes, structs, managers, renderers, terminal systems, data-source code, and platform services into focused files.
2. Do not over-split tiny types. If a type is under about 20 lines excluding imports, keep it with an associated file unless it has a strong independent reason.
3. Shared behavior should live in reusable core/shared modules. SwiftUI, WebUI, and TUI should not each reimplement bundle parsing, localization, conditions, row hydration, command interpolation, or state semantics differently.
4. Replace ad-hoc Swift dev scripts with Python where that makes local tooling easier and cross-platform.
5. Add or maintain local CI-equivalent commands so agents can reproduce failures before wasting CI cycles.
6. After app changes, kill the old dev build, build a new one, and launch it so the user can test the actual current build.
7. Test the real interactive behavior agents touched. Do not stop at compile success if the request was about UI, process cancellation, tooltips, resize behavior, startup timing, accessibility, or command execution.
8. When fixing PR feedback, make safe fixes, refuse incorrect feedback with a reason, do not merge until required checks and meaningful review threads are clean, and do not use destructive git operations unless explicitly requested.

### Experimental renderer completion checklist

1. Experimental renderers such as Flutter, Slint, Gio, and React Native must load the same WGS Extract bundle schema as SwiftUI/WebUI, including setup, config files, data sources, action conditions, confirmations, prechecks, and library rows.
2. They need full app-shell behavior: sidebar grouping, settings page, standard options, setup status, terminal tabs, process cancellation/close, command status, path picking, workspace opening, and benchmark markers.
3. They must parse `terminalTextDirection`, apply RTL-aware layout for RTL locales, expose explicit semantics around custom shell widgets, and keep implementation files below the megafile threshold.

## Short prompt to give future agents

Implement changes against the bundle contract, not just the visible surface. Preserve parity across SwiftUI, WebUI, TUI, and native ports; use WGS Extract to expose missing generic behavior; avoid legacy fallbacks; avoid megafiles; localize and annotate generated UI; run realistic app/CLI/accessibility checks; and launch the updated dev build when UI behavior changed.

## Session timeline

| Session | Span | Turns | Main user messages and decisions |
| --- | --- | ---: | --- |
| `gui-for-tui` in `~/src/gui-for-cli` | 2026-05-07 15:11 to 2026-05-08 22:24 UTC | 145 | Initial product definition: native macOS SwiftUI app that renders GUI front ends for CLI tools from portable bundles. Bundles can be folders or archives, contain setup steps, scripts, config, pages, controls, tooltips, actions, and a global terminal pane. Pivoted from TOML manifest to JSON, then to `manifest.json` plus `pages/`. WGS Extract is the first real bundle and should drive missing behavior. Repeated reminders covered native Apple styling, gray default buttons, red destructive actions, sidebar/page sizing, app identity, bundle icons, Pixi/setup scripts, settings/bootstrap, bundle workspace persistence, real process execution, disabled actions until variables are filled, file pickers, terminal tabs, kill/cancel semantics, exit code help, dynamic library lists, config editor, state-based row actions, data-source refresh, WGS command audit, page ordering, localization, RTL, and launch-after-build behavior. |
| `Add Cloc Make Command Excluding Gitignored` | 2026-05-08 04:02 UTC | 1 | Add a `make` command that runs cloc while excluding gitignored items. |
| `Add Translations For Eight Languages` | 2026-05-08 07:14 to 2026-05-09 04:37 UTC | 56 | Expanded locales far beyond English, added localization linting, moved strings into a `strings/` folder, required automatic locale detection and manual language selection, and defined untranslated strings as missing keys or values identical to English. Added greenfield rule: no backward compatibility shims or legacy fallbacks. Added realign flow requirements from WGS Extract, especially disk space estimates before long-running work. Required accessibility testing through macOS AX, extensive bug finding, non-pushed reviewable work when requested, tag cleanup in library rows, refactors to remove megafiles, Python dev scripts, built-in strings outside bundles, portable JSON state instead of UserDefaults, local CI-equivalent script, AX/axe testing, CSV/script-driven library data rather than embedded lists, no copying reference genomes except fixtures, fixed sidebar icon widths, extraction of managers, and folding tiny files back into associated files. |
| `Port Data-Driven UI To Web` | 2026-05-09 04:32 to 2026-05-09 07:43 UTC | 40 | Build a WebUI version of the SwiftUI data-driven implementation. User repeatedly corrected incompleteness: WebUI must match SwiftUI layout and behavior, use the same bundle workspace/config/state, show tooltips correctly, support sidebar and terminal resizing, close/cancel terminal tabs, use emoji and Bootstrap icons when SF Symbols are unavailable, expose icon-set and theme settings, support favicon from bundle icon, kill server process trees and all child CLI jobs, set title from bundle title, provide mobile layout that wraps nav horizontally, avoid sticky mobile top bar, keep favicon, migrate from EJS megafile to TypeScript modules, test loading, refactor `main.ts`/`app.ts`, add localization lint coverage, and finish PR review/CI feedback. |
| `Set Up Coderabbit For OSS Repo` | 2026-05-09 05:01 to 2026-05-09 06:27 UTC | 15 | Set up OSS code review tooling, investigate other free tools, apply to related repos owned by the user, fix AI review comments, and monitor multiple PRs. |
| `Implement Chronicle Tips Command` | 2026-05-09 06:58 UTC | 1 | Run `/chronicle tips`. |
| Related `gstack` session | 2026-05-09 07:17 UTC | 1 | Try related tooling with `wgsextract-cli` and `gui-for-cli` without installing. |
| Related `wgsextract-cli` session | 2026-05-09 07:36 to 2026-05-09 07:41 UTC | 2 | Remove old Python/web GUI support from WGS Extract because GUI functionality now belongs in `gui-for-cli`; link docs to `gui-for-cli`. |
| `Finalize GUI-For-CLI PR` | 2026-05-09 07:15 to 2026-05-09 07:47 UTC | 3 | Wrap up PR work only for `theontho/gui-for-cli/pull/1`, use CI PR autopilot behavior, identify blockers. |
| `GitHub Cloud Agent Setup Per OS` | 2026-05-09 08:18 to 2026-05-09 08:30 UTC | 4 | Make GitHub cloud agent setup OS-aware for Windows vs Linux; use branch `copilot/fix-github-actions`; answer setup-check question. |
| `Add Windows Native UI` | 2026-05-09 08:30 to 2026-05-09 08:47 UTC | 2 | Research and then plan a native Windows app. Emphasis: do not ignore WebUI; WebUI is the behavioral reference for platform-neutral manifest/runtime behavior. |
| `Polish Web UI Design` | 2026-05-09 08:48 UTC | 1 | Implement outstanding web redesign plan from `aidocs`. |
| `Add Nopilot Shell Alias` | 2026-05-09 08:33 to 2026-05-09 08:56 UTC | 2 | Add helper alias, then fix CI failure. |
| `Plan Android GUI Toolkit` | 2026-05-09 08:41 to 2026-05-09 08:56 UTC | 2 | Research Android implementation and move result to `aidocs`. |
| `iOS Implementation And Packaging Plan` | 2026-05-09 16:23 UTC | 1 | Move iOS plan to `aidocs`. |
| `Modernize Web UI Design` | 2026-05-09 17:24 to 2026-05-09 17:25 UTC | 2 | Implement the WebUI modernization research plan; use the branch name `webui-modern-redesign`. |
| `modernize webui for gui-for-cli` | 2026-05-09 18:28 to 2026-05-09 20:39 UTC | 20 | Separate agent session for WebUI modernization and PR/CI follow-up. |
| `Make Codecov Informational` | 2026-05-09 20:40 to 2026-05-09 22:26 UTC | 12 | Make Codecov informational, avoid CI failures from coverage reporting, fix PR review comments, and resolve merge conflicts. |
| `Add Make Kill Command And Coloring` | 2026-05-09 22:31 to 2026-05-10 04:09 UTC | 55 | Add `make kill`, colors, WebUI fixes, Bootstrap icon caching/vendor handling, better terminal behavior, translations, RTL parity, manifest terminal text direction, LTR path/terminal fields in RTL locales, mirrored icons where appropriate, sidebar hide button in RTL, and SF Pro font todo for Apple OS WebUI. User again corrected missing translations and RTL mismatches between SwiftUI and WebUI. |
| `Research App UI Design` | 2026-05-10 04:55 to 2026-05-10 06:43 UTC | 9 | Research TUI approach, move to `aidocs`, implement Swift TUI branch, add `make` run target, make TUI full-screen with scrollable sidebar/main/terminal panes, run and test real crashes, add color/UX polish, kill dangling processes. |
| `Refactor Web UI To TypeScript TUI` in `~/src/gui-for-cli2` | 2026-05-10 05:44 to 2026-05-10 06:43 UTC | 9 | Build TypeScript TUI from WebUI and `pi` TUI package. Requirements: make it attractive and colorized, bind to terminal size, internal scrolling for sidebar/main, path autocomplete, reduce flicker, Tab focus between panes, `q` quits the program, `+/-` resize terminal. |
| `Refactor And Split TUI Files` in `~/src/gui-for-cli2` | 2026-05-10 07:22 to 2026-05-10 19:14 UTC | 25 | Refactor TUI megafiles, share core data model/processing with WebUI, address PR feedback, handle light/dark terminal themes and system theme changes, allocate terminal pane height after first command, react to terminal resize automatically, add multiple terminal tabs and cancellation. |
| `Summarize Branch Changes` | 2026-05-10 07:24 to 2026-05-10 15:39 UTC | 11 | Summarize Swift TUI branch, compare Swift TUI vs TypeScript TUI, explain file sizes and what to port. |
| `macos-bench` | 2026-05-10 16:04 to 2026-05-10 20:10 UTC | 28 | Benchmark macOS surfaces: SwiftUI app, WebUI, TUI, native WKWebView, Tauri, Electron, Brave routes. User emphasized end-user distribution realities, app-specific vs runtime payload sizes, fairness of native runtime reuse, and keeping docs in `aidocs`. |
| `Create Windows Benchmark Report` | 2026-05-10 20:04 to 2026-05-10 20:08 UTC | 3 | Produce Windows benchmark report and discuss bootstrap installer size. |
| `Resolve Merge Conflict` | 2026-05-10 20:41 to 2026-05-11 01:25 UTC | 4 | Resolve conflicts and align generated/implementation changes. |
| `Resolve Merge Conflict` | 2026-05-11 01:36 to 2026-05-11 08:16 UTC | 31 | Continue conflict resolution and feature integration, especially performance/startup and generated outputs. |
| `Investigate SwiftUI Startup Performance` in `~/src/gui-for-cli2` | 2026-05-11 07:43 to 2026-05-11 09:04 UTC | 10 | Improve native SwiftUI startup from about 1.8s to 0.7s first real render; user asked for further startup wins and inspiration for other surfaces. |
| Go/Gio benchmark worktree | 2026-05-11 08:38 to 2026-05-11 09:07 UTC | 3 | Make Go/Gio PR branch match full app functionality and benchmark it; provide scripts/launch commands. |
| Flutter benchmark worktree | 2026-05-11 08:41 to 2026-05-11 08:54 UTC | 2 | Make Flutter PR branch match full app functionality and benchmark it; provide launch command. |
| React Native benchmark worktree | 2026-05-11 08:36 to 2026-05-11 09:07 UTC | 4 | Make React Native PR branch match full app functionality and benchmark it; provide a single working script command. |
| Slint benchmark worktree | 2026-05-11 08:58 UTC | 2 | Make Slint PR branch match full app functionality and benchmark it; provide launch command. |
| `Optimize Web Tauri TypeScript UIs` in `~/src/gui-for-cli3` | 2026-05-11 08:50 to 2026-05-11 09:13 UTC | 5 | Apply SwiftUI startup-performance lessons to WebUI, Tauri, and TypeScript TUI; report Tauri launch command and metrics; keep pushing for further startup improvements. |
