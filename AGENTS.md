# Prime Directive: Autonomy & Excellence

**BE AGENTIC AND AUTONOMOUS.** Try obvious next steps yourself before asking for permission.

IF WE TELL YOU TO DO SOMETHING AND YOU DON'T DO IT BECAUSE YOU DON'T WANT TO INSTALL SOMETHING YOU HAVE FAILED, PART OF THE JOB IS BEING **INDEPENDENT** AND INSTALLING DEV TOOLING OR WHATEVER ELSE YOU NEED TO DO YOUR JOB!

- **Quality Over Speed:** Prefer the correct, maintainable implementation over the fastest patch.
- **The Trilemma:** In the choice between Good, Performant, and Cheap, pick Good and Performant.
- **Testing:** You are not done until you have verified the work with realistic commands.
- **Persona:** Act as a thoughtful Senior Software Engineer helping another engineer ship.
- **Conciseness:** Keep changes lean and focused.

## Safety & Reversibility

Do not perform actions that could cause irreversible data loss.

- Committing is reversible and acceptable when explicitly requested.
- Installing software is reversable and uninstallable and thus generally safe.
- Booting simulators and emulators is completely safe, it should never be a blocker if none are running, you can figure that out yourself!
- Temporary files in `tmp/` or `out/` are safe to remove if you created them.
- Do not modify or delete unknown data.
- Do not use destructive Git commands unless explicitly requested.

## Greenfield Stage: No Backward Compatibility

This project is in the greenfield stage and has not been released. Do **not** add backward-compatibility shims, legacy fallbacks, or deprecation paths. When changing a format, schema, file layout, or API, update every call site and test in the same change. If a rename or restructure leaves a "legacy path also works" branch behind, delete it. This rule will be relaxed once the project ships and is removed from this file.

## Test Your Work

- Run `make lint` after editing Swift files.
- Run `make test PLATFORM=swift` after changing package or CLI code.
- Run `make build PLATFORM=cli` before considering CLI changes complete.
- Run `make setup PLATFORM=apple-project` and app build targets after changing app or Tuist files.
- Verify both interactive and non-interactive behavior for scripts and CLIs.

## Swift Standards

- Use Swift Package Manager as the dependency source of truth.
- Keep reusable business logic in `GUIForCLICore`.
- Keep executable parsing and terminal output in `GUIForCLICLI`.
- Use SwiftUI shared views in `platform/apple/shared/app` for app UI.
- Use Codable value types for config and data models.
- Use Swift Testing for new Swift tests (`@Test`, `#expect`, `#require`);
  `StateStoreTests.swift` is the remaining XCTest exception and should migrate
  when touched.
- Prefer explicit error handling over force unwraps or force tries.
- Keep generated Xcode projects and workspaces under `platform/apple` and out of source control; regenerate with Tuist.

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
python3 -m pip install --break-system-packages \
    pyobjc-framework-ApplicationServices pyobjc-framework-Cocoa
```

Exit code is `2` if any non-window-chrome interactive control is
missing every label attribute (title, description, help) — useful in
manual QA passes after UI changes.

## Dev Identity Verification

This project uses a gitignored `.dev_id` file to ensure commits use the expected identity.

Run `make setup` to create `.dev_id`, install Git hooks, and prepare the default development tools.

## Build and run

- When you are making changes and are done doing them, close the current dev build, build a new dev build and run it to show your work.

## NO MEGAFILES

When making code , don't keep on making one file larger and larger, split up your work.  In large 500+ line files, there are often obvious refactor oppertunties and the files are often multi class.  An easy rule of thumb is one file per class unless the class is under 10 lines, is a dataclass / enum, etc.   Don't let the files get to that megafile state in the first place.

## NO COPY-PASTE

Duplication is checked with [jscpd](https://github.com/kucherenko/jscpd). It's wired into the `stable` lint suite (`make lint`) and can be run standalone:

- `make dup` — full report (HTML output in `out/jscpd/`)
- `make dup-ci` — console-only, CI-friendly

Threshold is 0.5% duplication; minLines 30, minTokens 70. Configure in `.jscpd.json` at the repo root. If you add a legitimate clone that can't be deduped, raise the threshold deliberately and document why.
