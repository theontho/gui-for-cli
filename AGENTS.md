# Prime Directive: Autonomy & Excellence

**BE AGENTIC AND AUTONOMOUS.** Try obvious next steps yourself before asking for permission.

- **Quality Over Speed:** Prefer the correct, maintainable implementation over the fastest patch.
- **The Trilemma:** In the choice between Good, Performant, and Cheap, pick Good and Performant.
- **Testing:** You are not done until you have verified the work with realistic commands.
- **Persona:** Act as a thoughtful Senior Software Engineer helping another engineer ship.
- **Conciseness:** Keep changes lean and focused.

## Safety & Reversibility

Do not perform actions that could cause irreversible data loss.

- Committing is reversible and acceptable when explicitly requested.
- Temporary files in `tmp/`, `out/`, or `scratch/` are safe to remove if you created them.
- Do not modify or delete unknown data.
- Do not use destructive Git commands unless explicitly requested.

## Greenfield Stage: No Backward Compatibility

This project is in the greenfield stage and has not been released. Do **not** add backward-compatibility shims, legacy fallbacks, or deprecation paths. When changing a format, schema, file layout, or API, update every call site and test in the same change. If a rename or restructure leaves a "legacy path also works" branch behind, delete it. This rule will be relaxed once the project ships and is removed from this file.

## Test Your Work

- Run `make lint` after editing Swift files.
- Run `make test` after changing package or CLI code.
- Run `make build-cli` before considering CLI changes complete.
- Run `make project` and app build targets after changing app or Tuist files.
- Verify both interactive and non-interactive behavior for scripts and CLIs.

## Swift Standards

- Use Swift Package Manager as the dependency source of truth.
- Keep reusable business logic in `GUIForCLICore`.
- Keep executable parsing and terminal output in `GUIForCLICLI`.
- Use SwiftUI shared views in `Apps/Shared` for app UI.
- Use Codable value types for config and data models.
- Prefer explicit error handling over force unwraps or force tries.
- Keep generated Xcode projects and workspaces out of source control; regenerate with Tuist.

## CLI Design

- Keep `precheck`, `config`, and `run` subcommands working.
- Configuration should live in platform-standard Application Support paths.
- Redact keys, tokens, and secrets in displayed configuration.
- Support quiet and debug output modes.

## Accessibility smoke test (macOS)

`make ax-smoke` walks the AX tree of the running dev app and reports
node count, role distribution, unlabeled interactive controls, and the
active UI locale (heuristic). Requires Accessibility permission for
the terminal and pyobjc:

```bash
/opt/homebrew/bin/python3 -m pip install --break-system-packages \
    pyobjc-framework-ApplicationServices pyobjc-framework-Cocoa
```

Exit code is `2` if any non-window-chrome interactive control is
missing every label attribute (title, description, help) — useful in
manual QA passes after UI changes.

## Dev Identity Verification

This project uses a gitignored `.dev_id` file to ensure commits use the expected identity.

1. Run `swift scripts/dev-register.swift` to create `.dev_id`.
2. Run `swift scripts/setup-hooks.swift` to install Git hooks.

## Build and run

- When you are making changes and are done, with the macos app, close the current dev build, build a new dev build and run it to show your work.
