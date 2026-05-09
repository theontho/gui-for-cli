# Project Conventions for Code Review

## Project status
Greenfield, unreleased. **No backward compatibility.** When renaming/restructuring, update every call site and test in the same change. Do not leave "legacy path also works" branches.

## Architecture split
- `Sources/GUIForCLICore/` — reusable business logic
- `Sources/GUIForCLICLI/` — executable parsing & terminal output
- `Apps/Shared/` — shared SwiftUI views
- `WebUI/` — vanilla HTML/CSS/ES modules, no bundler
- `WebUI/shared/` — must run in both Node and browser (no Node-only APIs)
- `WebUI/server.mjs` — only place Node APIs (`fs`, `path`, `process`, `child_process`) may be used

## Swift conventions
- Use Swift Package Manager as the dependency source of truth
- Codable value types for config and data models
- Explicit error handling — avoid force unwraps (`!`) and force tries (`try!`) outside tests
- Generated Xcode projects/workspaces are not in source control (regenerated via Tuist)
- **Swift 6.2 type-checker pitfall:** Avoid inline literals mixing multiple sorted-dictionary `.map{...}.joined()` chains. Pre-bind each chain to a typed `[String]`.

## CLI design
- Keep `precheck`, `config`, and `run` subcommands working
- Configuration lives in platform-standard Application Support paths
- **Always redact** keys, tokens, and secrets in displayed configuration
- Support quiet and debug output modes
- Verify both interactive and non-interactive behavior

## WebUI conventions
- Vanilla ES modules — no frameworks, no bundlers, minimal deps
- Accessibility: every interactive control needs a label/aria-label; prefer semantic HTML
- Tests run via `node --test`; cover both happy and error paths

## Out of scope for review
- Style/formatting (handled by `swift-format` / `make lint`)
- Files under `.build/`, `DerivedData/`, `Derived/`, `*.xcodeproj/`, `*.xcworkspace/`, `out/`, `tmp/`, `scratch/`
- `Package.resolved`
