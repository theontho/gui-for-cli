# GUI for CLI

> [!WARNING]
> This project is a work in progress. The bundle schema, setup flow, and app UI are still changing and should not be treated as stable.

A SwiftUI starter app for building GUI front ends from small CLI-tool bundles.

![GUI for CLI macOS app showing the WGS Extract example bundle](docs/readme-screenshot.png)

## Features

- **Language:** Swift 6 with Swift Package Manager as the source of truth.
- **CLI:** `swift-argument-parser` with `precheck`, `config`, and `run` subcommands.
- **Apps:** Shared SwiftUI code for macOS first, with the iOS target retained for later support.
- **Bundles:** Codable JSON bundle/page/action/setup models with folder and archive loading.
- **Prototype UI:** Sidebar pages, form controls, action button rows, tooltips, and a global terminal-log pane with tabs.
- **Configuration:** JSON config in platform-standard Application Support paths with validation and redaction.
- **Quality:** `swift-format`, Swift Testing, release builds, app builds, and GitHub Actions CI.
- **Agent Friendly:** Includes `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` for AI-assisted development.

## Requirements

- Xcode 16 or newer with Swift 6.
- `swift-format`, available through recent Xcode toolchains as `swift format`.
- [Tuist](https://tuist.dev) for app workspace generation: `curl -Ls https://install.tuist.io | bash`.
- Optional: [mise](https://mise.jdx.dev) can install the pinned Tuist version from `.mise.toml`.
- GitHub CLI is optional, but `scripts/dev-register.swift` uses it when available.

## Getting Started

1. Install dependencies:
   ```bash
   swift package resolve
   ```
2. Run precheck:
   ```bash
   swift run gui-for-cli precheck
   ```
3. Initialize config:
   ```bash
   swift run gui-for-cli config init
   ```
4. Set up local development identity and hooks:
   ```bash
   make setup-dev
   ```
5. Run the CLI:
   ```bash
   swift run gui-for-cli run --name Swift
   ```
6. Generate the Xcode workspace:
   ```bash
   make project
   open GUIForCLI.xcworkspace
   ```

### Integrated app builds

The default app keeps the general `GUI for CLI` identity. For a more integrated bundle-specific build,
write a local, ignored identity config before generating the project:

```bash
mkdir -p tmp
printf '{ "embeddedBundlePath": "Examples/WGSExtract" }\n' > tmp/app-identity.json
./scripts/tuist.sh clean manifests
./scripts/tuist.sh generate --no-open
```

`embeddedBundlePath` reads `manifest.json` and uses its `displayName` for `CFBundleDisplayName`,
`CFBundleName`, and the built `.app` product name. You can also set `displayName` and `productName`
directly in `tmp/app-identity.json`. App icons remain asset catalog resources, so an integrated build
should also provide or replace the desired `AppIcon` assets. Delete `tmp/app-identity.json` and regenerate
after `./scripts/tuist.sh clean manifests` to return to the general app identity.

## Common Commands

- `make lint`: run `swift-format` lint checks.
- `make format`: format Swift source files in place.
- `make test`: run Swift package tests.
- `make build-cli`: build the release CLI.
- `make build-ios`: generate and build the iOS app for a simulator destination.
- `make build-macos`: generate and build the macOS app.
- `make precheck`: verify the local Apple development environment.

## Configuration

Configuration is stored at:

```text
$HOME/Library/Application Support/gui-for-cli/config.json
```

For isolated tests or scripts, set `GUI_FOR_CLI_CONFIG_DIR` to override the config directory.

View config:

```bash
swift run gui-for-cli config show
```

Overwrite config with defaults:

```bash
swift run gui-for-cli config init --force
```

## Bundles

A bundle is a folder or supported archive containing a `manifest.json`. The loader accepts:

- A folder containing `manifest.json`.
- A folder/archive containing one top-level child folder with `manifest.json`.
- A direct `manifest.json` file.
- `.zip`, `.tar`, `.tar.gz`, `.tgz`, and single-manifest `.gz` files on macOS.

Inspect the included example:

```bash
swift run gui-for-cli bundle inspect Examples/WGSExtract
```

Preview setup commands for a bundle:

```bash
swift run gui-for-cli bundle setup --dry-run Examples/WGSExtract
```

Create a copy of the example bundle:

```bash
swift run gui-for-cli bundle write-demo tmp/WGSExtract.gui-cli --force
```

Bundles can include a `strings.toml` file next to `manifest.json`. It is a flat key/value table:
GUI-facing strings in `manifest.json` are keys, and the loader replaces each key with the matching
value. If a key is missing, the app renders the key itself.

```toml
"bundle.displayName" = "My Tool"
"bundle.summary" = "A localized description."
"pages.main.title" = "Main"
"pages.main.summary" = "Run common commands."
"controls.main.inputs.input-file.tooltip" = "File to process."
"actions.main.commands.run.tooltip" = "Run the CLI with the current inputs."
```

### JSON schema

Top-level fields:

```json
{
  "id": "my-tool",
  "displayName": "bundle.displayName",
  "summary": "bundle.summary",
  "iconName": "terminal",
  "iconPath": "Assets/icon.png",
  "iconEmoji": "🧰",
  "sidebarIconStyle": "automatic",
  "pages": []
}
```

`iconPath` is optional and resolves relative to the bundle root. If no image is present, the app can render
`iconEmoji` into generated icon artwork, then falls back to `iconName` as an SF Symbol.
`sidebarIconStyle` controls what appears above the sidebar: `automatic`, `image`, `emoji`, `symbol`, or
`hidden`.

Setup steps use `setupScript`/`bundledScript`, `pathTool`, `homebrewPackage`, `pixiInstall`, or `pixiRun`.
Scripts and working directories must stay inside the bundle. Arguments and environment values can use
`{{bundleRoot}}` interpolation.

```json
{
  "setup": {
    "steps": [
      { "id": "pixi", "kind": "pathTool", "label": "setup.pixi.label", "value": "pixi", "optional": true },
      {
        "id": "install",
        "kind": "setupScript",
        "label": "setup.install.label",
        "value": "scripts/setup.sh",
        "environment": { "INSTALL_DIR": "{{bundleRoot}}/runtime/my-tool" }
      },
      {
        "id": "deps-check",
        "kind": "pixiRun",
        "label": "setup.deps-check.label",
        "value": "deps-check",
        "workingDirectory": "runtime/my-tool/app",
        "optional": true
      }
    ]
  }
}
```

Pages contain sections, sections contain controls and actions, and actions contain commands:

```json
{
  "pages": [
    {
      "id": "main",
      "title": "pages.main.title",
      "summary": "pages.main.summary",
      "iconName": "hammer",
      "sections": [
        {
          "id": "inputs",
          "title": "sections.main.inputs.title",
          "iconEmoji": "🧰",
          "controls": [
            {
              "id": "input-file",
              "label": "controls.main.inputs.input-file.label",
              "kind": "path",
              "tooltip": "controls.main.inputs.input-file.tooltip"
            }
          ],
          "actions": [
            {
              "id": "run",
              "title": "actions.main.inputs.run.title",
              "tooltip": "actions.main.inputs.run.tooltip",
              "iconName": "play.fill",
              "command": { "executable": "my-cli", "arguments": ["run"] }
            }
          ]
        }
      ]
    }
  ]
}
```

Pages, sections, and actions can use `"iconName"` for SF Symbols or `"iconEmoji"` for emoji. Actions can
also set `"iconOnly": true` while keeping `title` for tooltips and accessibility.

Additional generic controls can model richer CLI surfaces:

```json
{
  "id": "reference-library",
  "label": "controls.reference-library.label",
  "kind": "libraryList",
  "columns": [
    { "id": "name", "title": "columns.reference-library.name.title" },
    { "id": "status", "title": "columns.reference-library.status.title" }
  ],
  "rowTemplate": {
    "id": "{{id}}",
    "title": "{{name}}",
    "status": "{{status}}",
    "values": { "status": "{{status}}" }
  },
  "items": [
    { "id": "hg38", "name": "rows.reference-library.hg38.title", "status": "installed" }
  ],
  "rowActions": [
    {
      "id": "verify",
      "title": "actions.reference-library.verify.title",
      "iconName": "checkmark.seal",
      "iconOnly": true,
      "command": { "executable": "my-cli", "arguments": ["library", "verify", "{{row.id}}"] }
    }
  ]
}
```

```json
{
  "id": "tool-settings",
  "label": "controls.tool-settings.label",
  "kind": "configEditor",
  "configFile": { "path": "config/settings.toml", "format": "toml" },
  "settings": [
    {
      "id": "output-dir",
      "key": "output_dir",
      "label": "settings.output-dir.label",
      "kind": "path"
    }
  ]
}
```

`libraryList` renders a table with per-row actions. Use `rows` for fully authored static rows, or
`rowTemplate` plus `items` to define the row shape once and hydrate it from item data. Row action commands
can use `{{row.id}}` and `{{row.<value>}}` placeholders, plus regular control placeholders like
`{{output-dir}}`.
Action buttons stay disabled until every `{{...}}` placeholder in their command resolves to a non-empty
value. On macOS, action commands are launched as processes in the bundle root and stream output into
terminal tabs. Info buttons open clickable popover help while still supporting system hover help.
`configEditor` renders editable settings and writes a simple TOML file. Its settings-file path can be edited
or chosen with the native picker and is retained per bundle/control. Settings whose `key` or `id` matches a
normal control ID share the same value, so updating something like `ref_path` on another page updates the
settings editor too. Control kinds currently supported by the renderer are `text`, `path`, `dropdown`,
`toggle`, `checkboxGroup`, `infoGrid`, `libraryList`, and `configEditor`; `path` controls include a native
file/directory picker. Action roles are `primary`, `secondary`, and `destructive`.

## Git Hooks

Git does not automatically install hooks from a cloned repository. Opt in locally with:

```bash
make setup-dev
```

The installed `pre-commit` hook verifies your `.dev_id` and runs formatting lint. The `pre-push` hook verifies identity, runs tests, and builds the CLI.
