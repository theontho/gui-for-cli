# Changelog

All notable changes to this project are tracked here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Changed
- Bump the bundled WGSExtract CLI installer target to `v0.5.0`: alignment is ALT-aware on hs38DH and always marks duplicates, `info` shows whether an alignment was made that way (WGS Extract v4's weren't) and callers warn about it, microarray kits agree with real chips more closely (99.1% to 99.8% on AncestryDNA), `vcf trio` genotypes a trio jointly from their BAM/CRAMs, and `--gpu` aligns and calls on an NVIDIA GPU with Parabricks.
- Bump the bundled WGSExtract CLI installer target to `v0.4.3`: actions that pick a reference themselves use the one shipped beside a BAM over a library genome of another build (with hs38 installed, the mtDNA haplogroup action reported no haplogroup for the hg19 test genome), SpliceAI scores from Ensembl, and 23andMe v1/v2 microarray templates.
- Bump the bundled WGSExtract CLI installer target to `v0.4.2`: large reference downloads over 8 connections that resume, `ref status` listing all installed data, a usable PharmGKB annotation, `vcf pharmcat`, and a faster `vep --preset fast`.
- Bump the bundled WGSExtract CLI installer target to `v0.4.1`, whose Windows installer no longer needs Git (setup on a PC without Git failed installing Yleaf), runs GATK and HaploGrep on Windows, and removes MSYS2 on uninstall.
- Bump the bundled WGSExtract CLI installer target to `v0.4.0`, which adds the `--config` option the bundle now uses to keep its settings in the workspace, and fixes haplogroups for installs under paths with spaces.

## [0.3.8] - 2026-06-09

### Changed
- Bump the bundled WGSExtract CLI installer target to `v0.3.8` so new GUI builds pick up the microarray output fixes.

## [0.1.14] - 2026-06-08

### Added
- Local CI runner (`tools/ci/ci_local.py`) that mirrors the GitHub Actions pipeline; expose as `make ci` (full) and `make ci-fast` (skip iOS).
- Linux Swift Package CI job (Ubuntu, Swift 6.2 container) that runs `swift build` + `swift test` against `GUIForCLICore`.
- App-layer iOS guard: action buttons are disabled with an explanatory tooltip on iOS, where command execution is unsupported.
- Smarter pre-push hook: branches matching `release/*` run the full CI pipeline (incl. iOS build); other branches still use `--fast`.
- `LocaleMatchingTests` for `BundleSourceLoader.matchLocalizationCode` covering exact, region-stripped, Chinese script, and ordering paths.
- Windows admin setup mode for packaged WGSExtract installers.
- macOS and Windows worktree setup targets for installer lifecycle validation.
- SmartScreen install guidance on the WGSExtract download page.

### Changed
- Refactor blitz: split the four largest files into focused topic groups via Swift extensions.
  - `BundleSourceLoader` → entry + `+Manifest` + `+Localization`
  - `TerminalLogStore` → state/public API + `+Setup` + `+ProcessRunner`
  - `BundleManifestValidator` → entry + `+Pages` + `+Controls` + `+Helpers`; the monolithic `validate(_:)` body is now per-page/section/control helpers
  - `ControlRenderer` → view dispatch + `+Subviews` + `+DataSource`
- Round 2 splits: `DataSourceRunner` → entry + `+Process` (macOS); `ConfigFileBootstrapper` → entry + `+Toml` + `+Script`; `BundleSessionLoader` → entry + `+Workspace` + `+InitialState`.
- Moved reusable renderer/session helpers (`CommandRenderContext`, rendered commands, data sources, config IO, and bundle session loading) from `platform/apple/shared/app` into `GUIForCLICore`.
- CI workflow now runs the same Python script CI uses, so local `make ci` and remote CI cannot drift.
- Bumped `actions/checkout` to `@v6` (Node 24 runtime).

### Fixed
- `LocaleLinterRunner` strict mode regex no longer matches `, 0 errors`/`, 0 warnings`.
- `DataSourceRunner.signature` array literal split so Swift 6.2 type-checker doesn't time out on iOS Simulator builds.
- Cloudflare-blocked `install.tuist.io` script in CI replaced with `brew install tuist`.
- macOS CI runner now explicitly selects the newest installed Xcode so Swift 6.2 toolchain is active.
- WGSExtract macOS setup preflight behavior before bundled CLI install.
- WGSExtract installer lifecycle coverage for setup timing, app data creation, uninstall hooks, and cleanup.
