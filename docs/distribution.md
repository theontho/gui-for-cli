# Distribution packaging

This repository now has first-class distribution packaging for the desktop surfaces we intend to ship:

- **macOS SwiftUI app** → signed `.app` plus `.dmg`
- **macOS Tauri app** → signed/notarized Tauri `.app` plus `.dmg`
- **Linux Tauri app** → `.deb`, `.rpm`, Arch Linux `.pkg.tar.zst`, plus `.AppImage`
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

Run the macOS release cold install/uninstall smoke test:

```bash
make test PLATFORM=macos-cold-install
```

The test packages the SwiftUI DMG, mounts it, copies the `.app` into an isolated
temporary Applications directory, launches with an isolated `HOME`, verifies the
bundle-specific Application Support data is created, then removes both the app
and app data. Use `scripts/validate-macos-cold-install-uninstall.sh --help` for
options that intentionally test `/Applications` or the real home directory.

Packaged SwiftUI and Tauri releases default to the bundled WGSExtract app while generic distribution mode is still pending. To use a different embedded bundle, set these in `.devconfig.toml`:

```toml
[packaging]
embedded_bundle_path = "examples/WGSExtract"
app_name = "WGSExtract"
```

Then package as usual. The branded name is used for the app bundle name, installer/DMG name, and native window title. If you omit `app_name`, packaging falls back to the bundle directory name.
Embedded bundle packaging also reads `version` from the bundle's `manifest.json` and uses it as the packaged app version. For example, the bundled WGSExtract manifest currently sets `"version": "0.3.0"`, so installers and DMGs are named with `0.3.0` instead of GUI for CLI's own version. Use SemVer-compatible values because Tauri/NSIS and macOS marketing versions reject arbitrary tags. Set `app_version` in `.devconfig.toml` or `PACKAGE_APP_VERSION` / `EMBEDDED_APP_VERSION` to override the manifest version.

Embedded-bundle macOS builds use bundle identifier `dev.guiforcli.embed.<appname>`, normalized to lowercase letters and digits from the configured app name, or the bundle directory name when no app name is set; for example, `WGSExtract` becomes `dev.guiforcli.embed.wgsextract`.

Outputs land under `out/release/<platform>/`.

SwiftUI DMGs use the default Finder presentation unless the custom background
layout is explicitly enabled:

```toml
[packaging]
dmg_background = true
```

For one-off local builds, set `PACKAGE_DMG_BACKGROUND=1`.

## Signing and notarization

### SwiftUI macOS app

`make package PLATFORM=swift` builds an unsigned DMG by default.

The packaging flow regenerates the Tuist project with a branded app identity, switches the macOS bundle identifier to `dev.guiforcli.embed.<appname>`, sets the app marketing version from the embedded bundle, and points the built-in demo bundle at that embedded bundle.

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

### Tauri desktop apps

`make package PLATFORM=tauri` uses Tauri's native bundler. On Linux it builds
Debian/Ubuntu `.deb`, Fedora/RHEL/openSUSE `.rpm`, Arch Linux/Manjaro
`.pkg.tar.zst`, and universal AppImage packages by default. Tauri does not
provide a native Arch bundle target, so the Arch package installs the generated
AppImage under `/opt/<package>` with a pacman-managed launcher and desktop
entry.

The Tauri packaging flow stages the configured embedded bundle as the packaged built-in bundle and, when requested, renames the native app to `PACKAGE_APP_NAME`. The Tauri app version and generated installer names use the embedded bundle version by default.

Embedded bundle scripts can be split by platform under `scripts/windows`, `scripts/macos`, `scripts/linux`, `scripts/linux/<distro>`, and `scripts/posix`. Runtime resolution chooses the most specific folder for the host and falls back to `posix` for POSIX platforms. Every platform folder present in a bundle must include the full referenced script set, otherwise bundle validation fails.

Bundles can define `uninstall.steps` with the same step shape as `setup.steps`. The app exposes those as uninstall hooks for cleaning runtime state that lives outside normal app binaries or cannot be safely handled by deleting the bundle workspace alone.

On Windows, `python tools\platform.py test windows-tauri-lifecycle` builds the Tauri NSIS installer, silently installs it, launches the packaged app, runs bundle setup, runs bundle uninstall hooks, runs the native uninstaller, and checks cleanup.

For signed macOS Tauri builds, fill in `.devconfig.toml` with the same Developer ID values:

```toml
[apple.signing]
signing_identity = "Developer ID Application: Your Name (YOURTEAMID)"
development_team = "YOURTEAMID"
```

For notarization, provide the same notary credentials shown above.

### Linux and Windows Tauri apps

No signing is required to build the Linux `.deb` / `.rpm` / `.pkg.tar.zst` / `.AppImage` or the Windows NSIS installer. The packaging commands still produce end-user distributables.

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
