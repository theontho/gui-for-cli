import Foundation
import Testing

@testable import GUIForCLICore

@Test func bootstrapsConfiguredSettingsFile() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let manifest = CLIBundleManifest(
    id: "settings-bootstrap",
    displayName: "Settings Bootstrap",
    summary: "Creates missing config files.",
    iconName: "terminal",
    pages: [
      BundlePage(
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
                  path: "config/settings.toml",
                  bootstrap: ConfigBootstrapSpec(mode: .createIfMissing)),
                settings: [
                  ConfigSettingSpec(
                    id: "out_dir",
                    key: "output_directory",
                    label: "Output Directory",
                    kind: .path,
                    value: "out"),
                  ConfigSettingSpec(
                    id: "ref_path",
                    key: "reference_library",
                    label: "Reference Library",
                    kind: .path),
                ])
            ])
        ])
    ])

  let dryRunResults = try ConfigFileBootstrapper().bootstrap(
    manifest: manifest,
    rootURL: root,
    dryRun: true)
  let configURL = root.appendingPathComponent("config/settings.toml", isDirectory: false)
  #expect(dryRunResults.first?.status == .wouldCreate)
  #expect(FileManager.default.fileExists(atPath: configURL.path) == false)

  let results = try ConfigFileBootstrapper().bootstrap(manifest: manifest, rootURL: root)

  #expect(results.first?.status == .created)
  let text = try String(contentsOf: configURL, encoding: .utf8)
  let values = try FlatTomlDocument.parse(text)
  #expect(values["output_directory"] == "out")
  #expect(values["reference_library"] == "")

  let secondResults = try ConfigFileBootstrapper().bootstrap(manifest: manifest, rootURL: root)
  #expect(secondResults.first?.status == .skippedExisting)
}

@Test func bootstrapsSettingsFileFromBundledScript() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let scriptsURL = root.appendingPathComponent("scripts", isDirectory: true)
  try FileManager.default.createDirectory(at: scriptsURL, withIntermediateDirectories: true)
  let scriptURL = scriptsURL.appendingPathComponent("bootstrap-config.sh", isDirectory: false)
  try """
  #!/bin/sh
  set -eu
  printf '{"path":"%s/generated/settings.toml","values":{"output_directory":"script-out","reference_library":"%s/ref-lib"}}\\n' "$1" "$GUI_FOR_CLI_BUNDLE_WORKSPACE"
  """.write(to: scriptURL, atomically: true, encoding: .utf8)

  let manifest = CLIBundleManifest(
    id: "script-settings-bootstrap",
    displayName: "Script Settings Bootstrap",
    summary: "Creates config files from a script.",
    iconName: "terminal",
    pages: [
      BundlePage(
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
                  path: "{{bundleWorkspace}}/fallback/settings.toml",
                  bootstrap: ConfigBootstrapSpec(
                    mode: .createIfMissing,
                    script: ConfigBootstrapScriptSpec(
                      path: "scripts/bootstrap-config.sh",
                      arguments: ["{{bundleWorkspace}}"]))),
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
    ])

  let results = try ConfigFileBootstrapper().bootstrap(manifest: manifest, rootURL: root)
  let configURL = root.appendingPathComponent("generated/settings.toml", isDirectory: false)

  #expect(results.first?.status == .created)
  #expect(results.first?.url == configURL)
  let values = try FlatTomlDocument.parse(String(contentsOf: configURL, encoding: .utf8))
  #expect(values["output_directory"] == "script-out")
  #expect(values["reference_library"] == "\(root.path)/ref-lib")
}

@Test func mergeMissingTreatsEmptyExistingValuesAsUnset() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let configURL = root.appendingPathComponent("config/settings.toml", isDirectory: false)
  try FileManager.default.createDirectory(
    at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  try """
  output_directory = ""
  reference_library = "custom-ref"
  default_input_vcf = ""
  """.write(to: configURL, atomically: true, encoding: .utf8)

  let manifest = CLIBundleManifest(
    id: "settings-bootstrap",
    displayName: "Settings Bootstrap",
    summary: "Creates missing config values.",
    iconName: "terminal",
    pages: [
      BundlePage(
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
                  path: "config/settings.toml",
                  bootstrap: ConfigBootstrapSpec(mode: .mergeMissing)),
                settings: [
                  ConfigSettingSpec(
                    id: "out_dir",
                    key: "output_directory",
                    label: "Output Directory",
                    kind: .path,
                    value: "default-output"),
                  ConfigSettingSpec(
                    id: "ref_path",
                    key: "reference_library",
                    label: "Reference Library",
                    kind: .path,
                    value: "default-ref"),
                  ConfigSettingSpec(
                    id: "vcf_path",
                    key: "default_input_vcf",
                    label: "Input VCF",
                    kind: .path,
                    value: "default.vcf"),
                ])
            ])
        ])
    ])

  let results = try ConfigFileBootstrapper().bootstrap(manifest: manifest, rootURL: root)

  #expect(results.first?.status == .merged)
  let values = try FlatTomlDocument.parse(String(contentsOf: configURL, encoding: .utf8))
  #expect(values["output_directory"] == "default-output")
  #expect(values["reference_library"] == "custom-ref")
  #expect(values["default_input_vcf"] == "default.vcf")
}
