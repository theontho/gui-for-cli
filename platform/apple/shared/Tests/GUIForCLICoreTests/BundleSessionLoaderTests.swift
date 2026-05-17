import Foundation
import Testing

@testable import GUIForCLICore

@Test func bootstrapCanSkipInitialConfigReads() throws {
  let root = try temporaryDirectory()
  let bundleID = "bundle-session-loader-tests-\(UUID().uuidString)"
  let workspaceURL = AppPaths.bundleWorkspaceDirectory(for: bundleID)
  defer { try? FileManager.default.removeItem(at: root) }
  defer { try? FileManager.default.removeItem(at: workspaceURL) }

  let settingsPage = BundlePage(
    id: "settings",
    title: "Settings",
    summary: "Settings",
    sections: [
      PageSection(
        id: "paths",
        title: "Paths",
        controls: [
          ControlSpec(
            id: "tool-settings",
            label: "Tool Settings",
            kind: .configEditor,
            configFile: ConfigFileSpec(path: "config/settings.toml"),
            settings: [
              ConfigSettingSpec(
                id: "out_dir",
                key: "output_directory",
                label: "Output Directory",
                kind: .path,
                value: "default-out")
            ])
        ])
    ])
  let manifest = CLIBundleManifest(
    id: bundleID,
    displayName: "Bundle Session Loader Tests",
    summary: "Tests startup config loading.",
    iconName: "terminal",
    pages: [settingsPage])

  let encoder = JSONEncoder()
  try encoder.encode(manifest).write(
    to: root.appendingPathComponent("manifest.json", isDirectory: false))

  let configURL = workspaceURL.appendingPathComponent("config/settings.toml", isDirectory: false)
  try FileManager.default.createDirectory(
    at: configURL.deletingLastPathComponent(),
    withIntermediateDirectories: true)
  try "output_directory = \"restored-out\"\n".write(
    to: configURL,
    atomically: true,
    encoding: .utf8)

  let skipped = BundleSessionLoader.bootstrap(
    sourceRootURL: root,
    fallbackManifest: manifest,
    systemPreferences: [],
    prepareWorkspace: false,
    bootstrapConfig: false,
    loadInitialConfigValues: false)
  #expect(skipped.configValues["tool-settings.out_dir"] == "default-out")
  #expect(
    skipped.startupMessages.contains {
      $0.contains("Loaded settings from")
    } == false)

  let loaded = BundleSessionLoader.bootstrap(
    sourceRootURL: root,
    fallbackManifest: manifest,
    systemPreferences: [],
    prepareWorkspace: false,
    bootstrapConfig: false,
    loadInitialConfigValues: true)
  #expect(loaded.configValues["tool-settings.out_dir"] == "restored-out")
}

@Test func bootstrapPreparesWorkspaceConfigBeforeReturningSession() throws {
  let root = try temporaryDirectory()
  let bundleID = "bundle-session-loader-tests-\(UUID().uuidString)"
  let workspaceURL = AppPaths.bundleWorkspaceDirectory(for: bundleID)
  defer { try? FileManager.default.removeItem(at: root) }
  defer { try? FileManager.default.removeItem(at: workspaceURL) }

  let scriptsURL = root.appendingPathComponent("scripts", isDirectory: true)
  try FileManager.default.createDirectory(at: scriptsURL, withIntermediateDirectories: true)
  let scriptURL = scriptsURL.appendingPathComponent("bootstrap-config.sh", isDirectory: false)
  try """
  #!/bin/sh
  set -eu
  printf '{"values":{"output_directory":"%s/output","reference_library":"%s/reference"}}\\n' "$GUI_FOR_CLI_BUNDLE_WORKSPACE" "$GUI_FOR_CLI_BUNDLE_WORKSPACE"
  """.write(to: scriptURL, atomically: true, encoding: .utf8)

  let settingsPage = BundlePage(
    id: "settings",
    title: "Settings",
    summary: "Settings",
    sections: [
      PageSection(
        id: "paths",
        title: "Paths",
        controls: [
          ControlSpec(
            id: "tool-settings",
            label: "Tool Settings",
            kind: .configEditor,
            configFile: ConfigFileSpec(
              path: "{{bundleWorkspace}}/settings/config.toml",
              bootstrap: ConfigBootstrapSpec(
                mode: .mergeMissing,
                script: ConfigBootstrapScriptSpec(path: "scripts/bootstrap-config.sh"))),
            settings: [
              ConfigSettingSpec(
                id: "out_dir",
                key: "output_directory",
                label: "Output Directory",
                kind: .path),
              ConfigSettingSpec(
                id: "ref_path",
                key: "reference_library",
                label: "Reference Library",
                kind: .path),
            ])
        ])
    ])
  let manifest = CLIBundleManifest(
    id: bundleID,
    displayName: "Bundle Session Loader Tests",
    summary: "Tests startup config bootstrapping.",
    iconName: "terminal",
    pages: [settingsPage])
  let encoder = JSONEncoder()
  try encoder.encode(manifest).write(
    to: root.appendingPathComponent("manifest.json", isDirectory: false))

  let session = BundleSessionLoader.bootstrap(
    sourceRootURL: root,
    fallbackManifest: manifest,
    systemPreferences: [])

  #expect(session.bundleRootURL == workspaceURL)
  #expect(session.configValues["tool-settings.out_dir"] == "\(workspaceURL.path)/output")
  #expect(session.configValues["tool-settings.ref_path"] == "\(workspaceURL.path)/reference")
}
