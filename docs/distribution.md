# Distribution packaging

This repository now has first-class distribution packaging for the desktop surfaces we intend to ship:

- **macOS SwiftUI app** → signed `.app` plus `.dmg`
- **macOS Tauri app** → signed/notarized Tauri `.app` plus `.dmg`
- **Linux Tauri app** → `.deb` plus `.AppImage`
- **Windows Tauri app** → NSIS installer `.exe`

## Local commands

First, auto-detect local signing defaults and write them to `.devconfig.toml`:

```bash
uv run python scripts/dev.py signing autosetup
```

`autosetup` also reports expired or otherwise invalid code-signing identities that can confuse Xcode signing resolution. Remove expired identities from the keychain search list with:

```bash
uv run python scripts/dev.py signing delete-expired-identities
```

Use `--dry-run` to preview the identities before deleting them.

Generate the Apple workspace first when packaging the SwiftUI app:

```bash
make setup PLATFORM=apple-project
```

Build desktop distribution artifacts:

```bash
make package PLATFORM=swift
make package PLATFORM=tauri
```

To brand a packaged app around an embedded bundle, set these in `.devconfig.toml`:

```toml
[packaging]
embedded_bundle_path = "examples/WGSExtract"
app_name = "WGSExtract"
```

Then package as usual. The branded name is used for the app bundle name, installer/DMG name, and native window title. If you omit `app_name`, packaging falls back to the bundle directory name.

Outputs land under `out/release/<platform>/`.

## Signing and notarization

### SwiftUI macOS app

`make package PLATFORM=swift` builds an unsigned DMG by default.

When `EMBEDDED_BUNDLE_PATH` is set, the packaging flow also regenerates the Tuist project with a branded app identity and points the built-in demo bundle at that embedded bundle.

To produce a signed Developer ID export, fill in `.devconfig.toml`:

```toml
[apple.signing]
development_team = "YOURTEAMID"
team_id = "YOURTEAMID"
signing_identity = "Developer ID Application: Your Name (YOURTEAMID)"
```

The SwiftUI packager signs locally with the Developer ID Application identity in the keychain instead of relying on Xcode account export state. In CI, provide `APPLE_CERTIFICATE_P12` and `APPLE_CERTIFICATE_PASSWORD` so the workflow can import that identity before running `make package PLATFORM=swift`.

To notarize and staple the DMG as well, store credentials in a notarytool keychain profile:

```bash
xcrun notarytool store-credentials your-notarytool-keychain-profile \
  --apple-id you@example.com \
  --password xxxx-xxxx-xxxx-xxxx \
  --team-id YOURTEAMID
```

Then fill in:

```toml
[apple.signing]
notary_profile = "your-notarytool-keychain-profile"
```

The SwiftUI packaging flow builds the release app, signs it with the Developer ID Application identity, creates and signs a DMG, optionally notarizes it, and staples both the DMG and the app.

### Tauri macOS app

`make package PLATFORM=tauri` uses Tauri's native bundler.

When `EMBEDDED_BUNDLE_PATH` is set, the Tauri packaging flow stages that bundle as the packaged built-in bundle and, when requested, renames the native app to `PACKAGE_APP_NAME`.

For signed macOS Tauri builds, fill in `.devconfig.toml` with the same Developer ID values:

```toml
[apple.signing]
signing_identity = "Developer ID Application: Your Name (YOURTEAMID)"
development_team = "YOURTEAMID"
```

For notarization, provide the same notary credentials shown above.

### Linux and Windows Tauri apps

No signing is required to build the Linux `.deb` / `.AppImage` or the Windows NSIS installer. The packaging commands still produce end-user distributables.

## CI / release automation

`.github/workflows/distribution.yml` builds the same artifacts on GitHub Actions for:

- `workflow_dispatch`
- `v*` tags

The macOS jobs import an Apple distribution certificate when these secrets are present:

- `APPLE_CERTIFICATE_P12`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_DEVELOPMENT_TEAM`
- `APPLE_SIGNING_IDENTITY` (recommended for Tauri)
- optional notarization secrets:
  - `APPLE_ID`
  - `APPLE_APP_SPECIFIC_PASSWORD`
  - `APPLE_TEAM_ID`

The workflow uploads packaged artifacts from `out/release/swiftui` and `out/release/tauri`.
