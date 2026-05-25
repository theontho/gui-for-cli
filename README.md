# GUI for CLI

GUI for CLI turns a portable CLI-tool bundle into an installable desktop app. The production frontends are `swiftui-macos` and `tauri-webui`; the Swift CLI and TypeScript Web UI server support development, packaging, setup, and automation behind those frontends.

![GUI for CLI macOS app showing the WGS Extract example bundle](docs/readme-screenshot.png)

## Production frontends

| Frontend | Path | Command |
| --- | --- | --- |
| `swiftui-macos` | `platform/apple/swiftui` plus `platform/apple/shared` | `make run PLATFORM=swiftui-macos` |
| `tauri-webui` | `platform/typescript/web` plus `platform/typescript/web/packagers/tauri` | `make run PLATFORM=tauri` |

The first real app developed with GUI for CLI is the bundled WGSExtract interface in `examples/WGSExtract`. It exercises setup steps, long-running commands, dynamic data sources, localization, configuration, terminal output, file pickers, and release packaging against a realistic genomics workflow instead of a toy demo.

Desktop GUI experiments and benchmark results now live in [`docs/desktop-gui-experiments.md`](docs/desktop-gui-experiments.md). That document keeps the research history out of the README while preserving why SwiftUI macOS and Tauri WebUI are the two product frontends.

## Static project site

The generated local site lives in `site/` and is built from Markdown sources in `site_src/`:

```bash
python3 scripts/build_site.py
open site/index.html
```

The site explains the tool, the frontend decision, the experimental renderer results, and how WGSExtract drove the first production bundle.

## Requirements

- Xcode 16 or newer with Swift 6 and `swift format` for the SwiftUI macOS frontend and CLI.
- [Tuist](https://tuist.dev) for Apple workspace generation.
- Node.js 18 or newer for the TypeScript Web UI server and Tauri WebUI workflow.
- Rust/Cargo when building the Tauri desktop app.
- Python 3.11 or newer for repository tooling.
- Optional: [mise](https://mise.jdx.dev) can install the pinned Tuist version from `.mise.toml`.
- On Windows, run `.\make.ps1 setup` and `.\make.ps1 precheck` to prepare the dev environment, then call `python tools\platform.py ...` directly for build/test/package tasks.

Experimental renderers may require extra language SDKs or native libraries; see [`docs/desktop-gui-experiments.md`](docs/desktop-gui-experiments.md) and `docs/ai/platforms/` when working on those prototypes.

## Getting started

```bash
make setup
make precheck
swift run --package-path platform/apple gui-for-cli config init
make setup PLATFORM=apple-project
open platform/apple/GUIForCLI.xcworkspace
```

Run the production frontends with the WGSExtract bundle:

```bash
make run PLATFORM=swiftui-macos BUNDLE=examples/WGSExtract
make run PLATFORM=tauri BUNDLE=examples/WGSExtract
```

The CLI remains available directly for bundle inspection, setup, and command rendering:

```bash
swift run --package-path platform/apple gui-for-cli run --name Swift
```

## Common commands

| Command | Purpose |
| --- | --- |
| `make lint` | Run the stable lint suite through the platform runner. |
| `make platforms` | List platform names with their runner capabilities. |
| `make test PLATFORM=swift` | Run Swift package tests. |
| `make build PLATFORM=cli` | Build the release CLI. |
| `make test PLATFORM=webui` | Build and run TypeScript Web UI/shared tests. |
| `make build PLATFORM=swiftui-macos` | Build the native macOS frontend. |
| `make build PLATFORM=tauri` | Build the Tauri WebUI desktop frontend. |
| `make package PLATFORM=swift` | Build a macOS SwiftUI distribution folder with `.app` and `.dmg` output; signs/notarizes when Apple credentials are configured. |
| `make package PLATFORM=tauri` | Build Tauri desktop distribution artifacts for the current OS. |
| `make release-build SUITE=stable` | Build the stable release targets. |
| `python3 scripts/build_site.py` | Regenerate the static project site into `site/`. |
| `make ci` / `make ci-fast` | Run local CI checks. |

## Bundles

A bundle is a folder or supported archive containing `manifest.json`. The loader accepts a bundle folder, a folder/archive with one top-level child containing `manifest.json`, a direct `manifest.json` file, and `.zip`, `.tar`, `.tar.gz`, `.tgz`, or single-manifest `.gz` archives on macOS.

```bash
swift run --package-path platform/apple gui-for-cli bundle inspect examples/WGSExtract
swift run --package-path platform/apple gui-for-cli bundle setup --dry-run examples/WGSExtract
swift run --package-path platform/apple gui-for-cli bundle write-demo tmp/WGSExtract.gui-cli --force
```

Bundles can include `strings.toml` and `strings.<language-code>.toml` localization tables next to `manifest.json`. Schema files live in `docs/schema/manifest.schema.json` and `docs/schema/page.schema.json`.

## Configuration

Configuration is stored in the platform Application Support directory:

```text
$HOME/Library/Application Support/gui-for-cli/config.json
```

Set `GUI_FOR_CLI_CONFIG_DIR` to override the config directory for isolated tests or scripts.

```bash
swift run --package-path platform/apple gui-for-cli config show
swift run --package-path platform/apple gui-for-cli config init --force
```

## Distribution packaging

See [`docs/distribution.md`](docs/distribution.md) for the full signing, notarization, and CI artifact flow.

Preferred local signing setup flow:

```bash
uv run python scripts/dev.py signing autosetup
```

If autosetup reports expired identities, remove them with:

```bash
uv run python scripts/dev.py signing delete-expired-identities
```

Use `--dry-run` to preview the cleanup.

Quick start:

```bash
make setup PLATFORM=apple-project
make package PLATFORM=swift
make package PLATFORM=tauri
```

Distribution packaging defaults to the bundled WGSExtract app until generic distribution mode is implemented. Set `packaging.embedded_bundle_path` and `packaging.app_name` in `.devconfig.toml` to package a different bundle; embedded-bundle builds use `dev.guiforcli.embed.<appname>`, such as `dev.guiforcli.embed.wgsextract`.

SwiftUI DMGs use the default Finder presentation unless `packaging.dmg_background = true` or `PACKAGE_DMG_BACKGROUND=1` opts into the custom background layout.

Signed SwiftUI releases require a Developer ID Application identity in the keychain locally, or `APPLE_CERTIFICATE_P12` / `APPLE_CERTIFICATE_PASSWORD` secrets in CI.

`out/release/swiftui/` contains the SwiftUI macOS `.app` and `.dmg`, while `out/release/tauri/` contains the current-platform Tauri distributables.

## Integrated app builds

The default app keeps the general `GUI for CLI` identity and macOS bundle identifier `dev.guiforcli.generic`. For a bundle-specific local build, write an ignored identity file before regenerating the project:

```bash
mkdir -p tmp
printf '{ "embeddedBundlePath": "examples/WGSExtract" }\n' > tmp/app-identity.json
cd platform/apple
../../scripts/tuist.sh clean manifests
../../scripts/tuist.sh generate --no-open
```

`embeddedBundlePath` reads the bundle `manifest.json` and uses its configured app name or bundle directory name as the base for generated app display and product names. Shipped bundle-specific products add the platform/distribution suffix, such as `macOS` or `macOS WebUI`, while release packaging sets `bundleIdentifierName` so the macOS bundle identifier stays `dev.guiforcli.embed.<appname>` from the normalized base app name. Delete `tmp/app-identity.json` and regenerate after `cd platform/apple && ../../scripts/tuist.sh clean manifests` to return to the generic app identity.
