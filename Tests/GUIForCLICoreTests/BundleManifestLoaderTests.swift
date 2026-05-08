import Foundation
import Testing

@testable import GUIForCLICore

@Test func decodesDemoJSONManifest() throws {
  let manifestURL = DemoBundle.wgsExtractResourceRootURL.appendingPathComponent(
    "manifest.json", isDirectory: false)
  let rawManifest = try ManifestJSONDecoder().decode(
    CLIBundleManifest.self, from: Data(contentsOf: manifestURL))
  let manifest = try BundleSourceLoader().load(from: DemoBundle.wgsExtractResourceRootURL).manifest

  #expect(manifest.id == "wgs-extract")
  #expect(rawManifest.displayName == "bundle.displayName")
  #expect(manifest.displayName == "WGS Extract")
  #expect(manifest.iconName == "point.3.connected.trianglepath.dotted")
  #expect(manifest.iconPath == "Assets/icon.png")
  #expect(manifest.iconEmoji == "🧬")
  #expect(manifest.sidebarIconStyle == .automatic)
  #expect(manifest.setup.steps.contains { $0.kind == .setupScript })
  #expect(manifest.setup.steps.contains { $0.kind == .pixiRun && $0.optional })
  #expect(manifest.exitCodeReference.first { $0.code == 127 }?.title == "Command not found")
  #expect(manifest.exitCodeReference.first { $0.code == 130 }?.severity == .warning)
  #expect(
    rawManifest.pageFiles == [
      "workflow.json", "info-bam.json", "extract.json", "microarray.json", "ancestry.json",
      "vcf.json", "fastq.json", "pet-analysis.json", "library.json", "settings.json",
    ])
  #expect(
    manifest.pages.map(\.id) == [
      "workflow", "info-bam", "extract", "microarray", "ancestry", "vcf", "fastq",
      "pet-analysis", "library", "settings",
    ])
  #expect(manifest.pages.first { $0.id == "library" }?.iconName == "books.vertical")
  #expect(manifest.pages.first { $0.id == "vcf" }?.sections.count == 4)
  #expect(
    manifest.pages.first { $0.id == "microarray" }?.sections[1].controls[0].options.count == 19)
  #expect(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "genome-management" }?
      .controls.first?.kind == .libraryList)
  #expect(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "genome-management" }?
      .controls.first?.rowTemplate?.id == "{{id}}")
  #expect(
    manifest.pages.first { $0.id == "settings" }?.sections.first { $0.id == "settings-paths" }?
      .controls.first?.kind == .configEditor)
  let settingsControl = try #require(
    manifest.pages.first { $0.id == "settings" }?.sections.first { $0.id == "settings-paths" }?
      .controls.first)
  #expect(settingsControl.configFile?.path == "{{bundleWorkspace}}/settings/config.toml")
  #expect(settingsControl.configFile?.bootstrap?.mode == .createIfMissing)
  #expect(
    settingsControl.configFile?.bootstrap?.script?.path
      == "scripts/bootstrap-wgsextract-config.sh")
  #expect(settingsControl.settings.first { $0.id == "ref_path" }?.key == "reference_library")
}

@Test func demoBundleAppliesLocalizationTable() throws {
  let manifest = DemoBundle.wgsExtract

  #expect(manifest.displayName == "WGS Extract")
  #expect(
    manifest.pages.first { $0.id == "info-bam" }?.summary
      == "BAM and CRAM are compressed files containing DNA sequences aligned to a reference genome. Use this page to identify the data build, check sequence quality, calculate coverage, or convert alignment formats."
  )
  #expect(
    manifest.pages.first { $0.id == "info-bam" }?.sections.first { $0.id == "inputs" }?
      .controls.first { $0.id == "bam_path" }?.tooltip == "Input BAM or CRAM file.")
  #expect(
    manifest.pages.flatMap(\.sections).flatMap(\.actions).first { $0.id == "vcf-vep-run" }?
      .tooltip?.contains("Ensembl Variant Effect Predictor") == true)
}

@Test func parsesFlatLocalizationTomlAndResolvesKeys() throws {
  let table = try BundleStringTable(
    tomlData: Data(
      """
      "bundle.displayName" = "Localized Tool"
      "bundle.summary" = "Localized summary."
      "pages.main.title" = "Main Page"
      "pages.main.summary" = \"\"\"
      A longer
      multiline summary.
      \"\"\"
      "controls.input.label" = "Input"
      "controls.input.tooltip" = "Input help."
      "exitCodes.default.126.title" = "Cannot Execute"
      "exitCodes.default.126.summary" = "The localized bundle explains executable permission failures."
      "exitCodes.custom.127.title" = "Tool Missing"
      "exitCodes.custom.127.summary" = "Install the localized tool runtime first."
      """.utf8))

  let manifest = CLIBundleManifest(
    id: "localized",
    displayName: "bundle.displayName",
    summary: "bundle.summary",
    iconName: "terminal",
    exitCodeReference: [
      ExitCodeReferenceEntry(
        code: 127,
        title: "exitCodes.custom.127.title",
        summary: "exitCodes.custom.127.summary")
    ],
    pages: [
      BundlePage(
        id: "main",
        title: "pages.main.title",
        summary: "pages.main.summary",
        sections: [
          PageSection(
            id: "inputs",
            controls: [
              ControlSpec(
                id: "input",
                label: "controls.input.label",
                kind: .text,
                tooltip: "controls.input.tooltip")
            ])
        ])
    ])

  let localized = try BundleLocalizationResolver(table: table).localized(manifest)

  #expect(localized.displayName == "Localized Tool")
  #expect(localized.pages[0].title == "Main Page")
  #expect(localized.pages[0].summary == "A longer\nmultiline summary.")
  #expect(localized.pages[0].sections[0].controls[0].tooltip == "Input help.")
  #expect(localized.exitCodeReference.first { $0.code == 126 }?.title == "Cannot Execute")
  #expect(localized.exitCodeReference.first { $0.code == 127 }?.title == "Tool Missing")
}

@Test func missingLocalizationRendersKey() throws {
  let table = BundleStringTable(values: ["bundle.displayName": "Localized Tool"])
  let manifest = CLIBundleManifest(
    id: "localized",
    displayName: "bundle.displayName",
    summary: "bundle.summary",
    iconName: "terminal",
    pages: [
      BundlePage(
        id: "main",
        title: "pages.main.title",
        summary: "pages.main.summary",
        sections: [
          PageSection(id: "inputs")
        ])
    ])

  let localized = try BundleLocalizationResolver(table: table).localized(manifest)

  #expect(localized.displayName == "Localized Tool")
  #expect(localized.summary == "bundle.summary")
  #expect(localized.pages[0].title == "pages.main.title")
}

@Test func rejectsManifestWithoutPages() throws {
  let data = Data(
    """
    {
      "id": "empty",
      "displayName": "Empty",
      "summary": "No pages."
    }
    """.utf8)

  #expect(throws: BundleValidationError.noPages) {
    _ = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: data)
  }
}

@Test func loadsBundleFolder() throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  try BundleSourceLoader().writeDemoBundle(to: directory, overwrite: true)
  let manifestURL = directory.appendingPathComponent("manifest.json", isDirectory: false)

  let loaded = try BundleSourceLoader().load(from: directory)

  #expect(loaded.manifest.id == "wgs-extract")
  #expect(loaded.manifestURL.resolvingSymlinksInPath() == manifestURL.resolvingSymlinksInPath())
  #expect(loaded.isTemporary == false)
}

@Test func loadsNestedBundleFolder() throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let nested = directory.appendingPathComponent("WGSExtract.gui-cli", isDirectory: true)
  try BundleSourceLoader().writeDemoBundle(to: nested, overwrite: true)
  let manifestURL = nested.appendingPathComponent("manifest.json", isDirectory: false)

  let loaded = try BundleSourceLoader().load(from: directory)

  #expect(loaded.manifestURL.resolvingSymlinksInPath() == manifestURL.resolvingSymlinksInPath())
  #expect(loaded.rootURL.resolvingSymlinksInPath() == nested.resolvingSymlinksInPath())
}

@Test func loadsArchiveThroughInjectedExtractor() throws {
  let archive = FileManager.default.temporaryDirectory
    .appendingPathComponent("bundle-\(UUID().uuidString).zip", isDirectory: false)
  try Data("stub".utf8).write(to: archive)
  defer { try? FileManager.default.removeItem(at: archive) }

  let temporaryRoot = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: temporaryRoot) }
  let loader = BundleSourceLoader(
    archiveExtractor: CopyingArchiveExtractor(),
    temporaryRoot: temporaryRoot
  )

  let loaded = try loader.load(from: archive)

  #expect(loaded.manifest.id == "wgs-extract")
  #expect(loaded.isTemporary == true)
}

@Test func plansSetupScriptAndPixiCommands() throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let scripts = directory.appendingPathComponent("scripts", isDirectory: true)
  try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
  let scriptURL = scripts.appendingPathComponent("setup.sh", isDirectory: false)
  try "#!/bin/sh\necho setup\n".write(to: scriptURL, atomically: true, encoding: .utf8)

  let data = Data(
    """
    {
      "id": "setup-test",
      "displayName": "Setup Test",
      "summary": "Exercises setup planning.",
      "iconPath": "Assets/icon.png",
      "setup": {
        "steps": [
          {
            "id": "script",
            "label": "Install",
            "kind": "setupScript",
            "value": "scripts/setup.sh",
            "arguments": ["--install-dir", "{{bundleRoot}}/app"],
            "environment": {"CACHE_DIR": "{{bundleRoot}}/.cache"}
          },
          {
            "id": "pixi",
            "label": "Install Pixi environment",
            "kind": "pixiInstall",
            "value": "pixi",
            "workingDirectory": "app"
          },
          {
            "id": "deps",
            "label": "Check dependencies",
            "kind": "pixiRun",
            "value": "deps-check",
            "optional": true
          }
        ]
      },
      "pages": [
        {
          "id": "main",
          "title": "Main",
          "summary": "Main page.",
          "systemImage": "terminal",
          "sections": [{"id":"main-section"}]
        }
      ]
    }
    """.utf8)
  let manifest = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: data)

  let commands = try SetupCommandPlanner().plan(for: manifest, rootURL: directory)

  #expect(commands[0].arguments == [scriptURL.path, "--install-dir", "\(directory.path)/app"])
  #expect(commands[0].environment["CACHE_DIR"] == "\(directory.path)/.cache")
  #expect(commands[1].arguments == ["pixi", "install"])
  #expect(commands[1].workingDirectory.path == directory.appendingPathComponent("app").path)
  #expect(commands[2].arguments == ["pixi", "run", "deps-check"])
  #expect(commands[2].optional)
}

@Test func rejectsUnsafeSetupAndIconPaths() throws {
  let unsafeIcon = Data(
    """
    {
      "id": "unsafe-icon",
      "displayName": "Unsafe Icon",
      "summary": "Bad icon.",
      "iconPath": "../icon.png",
      "pages": [{"id":"main","title":"Main","summary":"Main page.","sections":[{"id":"main-section"}]}]
    }
    """.utf8)
  #expect(throws: BundleValidationError.invalidRelativePath(path: "iconPath", value: "../icon.png"))
  {
    _ = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: unsafeIcon)
  }

  let unsafeScript = Data(
    """
    {
      "id": "unsafe-script",
      "displayName": "Unsafe Script",
      "summary": "Bad script.",
      "setup": {
        "steps": [
          {"id":"setup","label":"Setup","kind":"setupScript","value":"../setup.sh"}
        ]
      },
      "pages": [{"id":"main","title":"Main","summary":"Main page.","sections":[{"id":"main-section"}]}]
    }
    """.utf8)
  #expect(
    throws: BundleValidationError.invalidRelativePath(
      path: "setup.steps.setup.value", value: "../setup.sh")
  ) {
    _ = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: unsafeScript)
  }
}

@Test func writeDemoBundleIncludesSetupScript() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let directory = root.appendingPathComponent("WGSExtract.gui-cli", isDirectory: true)

  try BundleSourceLoader().writeDemoBundle(to: directory, overwrite: false)

  let manifestURL = directory.appendingPathComponent("manifest.json", isDirectory: false)
  let scriptURL = directory.appendingPathComponent(
    "scripts/setup-wgsextract-pixi.sh", isDirectory: false)
  let bootstrapScriptURL = directory.appendingPathComponent(
    "scripts/bootstrap-wgsextract-config.sh", isDirectory: false)
  let runScriptURL = directory.appendingPathComponent(
    "scripts/run-wgsextract.sh", isDirectory: false)
  #expect(FileManager.default.fileExists(atPath: manifestURL.path))
  #expect(
    FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("strings.toml", isDirectory: false).path))
  #expect(FileManager.default.fileExists(atPath: scriptURL.path))
  #expect(FileManager.default.fileExists(atPath: bootstrapScriptURL.path))
  #expect(FileManager.default.fileExists(atPath: runScriptURL.path))
  #expect(
    FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Assets/icon.png", isDirectory: false).path))

  let attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
  let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
  #expect(permissions.intValue & 0o111 != 0)
  let bootstrapAttributes = try FileManager.default.attributesOfItem(
    atPath: bootstrapScriptURL.path)
  let bootstrapPermissions = try #require(bootstrapAttributes[.posixPermissions] as? NSNumber)
  #expect(bootstrapPermissions.intValue & 0o111 != 0)
  let runScriptAttributes = try FileManager.default.attributesOfItem(atPath: runScriptURL.path)
  let runScriptPermissions = try #require(runScriptAttributes[.posixPermissions] as? NSNumber)
  #expect(runScriptPermissions.intValue & 0o111 != 0)
}

@Test func syncBundleWorkspacePreservesRuntime() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let workspace = root.appendingPathComponent("wgs-extract", isDirectory: true)
  let runtime = workspace.appendingPathComponent("runtime/wgsextract-cli", isDirectory: true)
  try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
  let marker = runtime.appendingPathComponent("installed.txt", isDirectory: false)
  try "keep".write(to: marker, atomically: true, encoding: .utf8)

  try BundleSourceLoader().syncBundleWorkspace(
    from: DemoBundle.wgsExtractResourceRootURL,
    to: workspace)

  #expect(FileManager.default.fileExists(atPath: marker.path))
  #expect(
    FileManager.default.fileExists(
      atPath: workspace.appendingPathComponent("manifest.json", isDirectory: false).path))
  let runScriptURL = workspace.appendingPathComponent(
    "scripts/run-wgsextract.sh", isDirectory: false)
  let runScriptAttributes = try FileManager.default.attributesOfItem(atPath: runScriptURL.path)
  let runScriptPermissions = try #require(runScriptAttributes[.posixPermissions] as? NSNumber)
  #expect(runScriptPermissions.intValue & 0o111 != 0)
}

@Test func decodesEmojiIconFallback() throws {
  let data = Data(
    """
    {
      "id": "emoji-icon",
      "displayName": "Emoji Icon",
      "summary": "Uses generated emoji artwork.",
      "iconEmoji": "🧰",
      "pages": [
        {
          "id": "main",
          "title": "Main",
          "summary": "Main page.",
          "sections": [{"id":"main-section"}]
        }
      ]
    }
    """.utf8)

  let manifest = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: data)

  #expect(manifest.iconEmoji == "🧰")
  #expect(manifest.iconName == "terminal")
}

@Test func decodesSidebarIconStyles() throws {
  for style in SidebarIconStyle.allCases {
    let data = Data(
      """
      {
        "id": "sidebar-\(style.rawValue)",
        "displayName": "Sidebar \(style.rawValue)",
        "summary": "Checks sidebar icon style.",
        "sidebarIconStyle": "\(style.rawValue)",
        "pages": [
          {
            "id": "main",
            "title": "Main",
            "summary": "Main page.",
            "sections": [{"id":"main-section"}]
          }
        ]
      }
      """.utf8)

    let manifest = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: data)

    #expect(manifest.sidebarIconStyle == style)
  }
}

@Test func decodesLibraryListAndConfigEditorControls() throws {
  let data = Data(
    """
    {
      "id": "advanced",
      "displayName": "Advanced",
      "summary": "Uses rich generic controls.",
      "pages": [
        {
          "id": "main",
          "title": "Main",
          "summary": "Main page.",
          "iconName": "square.grid.2x2",
          "sections": [
            {
              "id": "library",
              "iconEmoji": "📚",
              "controls": [
                {
                  "id": "refs",
                  "label": "Reference Library",
                  "kind": "libraryList",
                  "columns": [
                    { "id": "name", "title": "Name" },
                    { "id": "status", "title": "Status" }
                  ],
                  "rowTemplate": {
                    "id": "{{id}}",
                    "title": "{{name}}",
                    "status": "{{status}}",
                    "values": { "status": "{{status}}" }
                  },
                  "items": [
                    { "id": "hg38", "name": "HG38", "status": "installed" }
                  ],
                  "rowActions": [
                    {
                      "id": "verify",
                      "title": "Verify",
                      "iconName": "checkmark.seal",
                      "iconOnly": true,
                   "command": {
                     "executable": "tool",
                     "arguments": ["verify", "{{row.id}}", "{{row.status}}"],
                     "optionalArguments": [["--label", "{{row.label}}"]]
                   }
                    }
                  ]
                },
                {
                  "id": "settings",
                  "label": "Settings",
                  "kind": "configEditor",
                  "configFile": {
                    "path": "config/settings.toml",
                    "format": "toml",
                    "bootstrap": { "mode": "createIfMissing" }
                  },
                  "settings": [
                    {
                      "id": "out",
                      "key": "output_dir",
                      "label": "Output Directory",
                      "kind": "path",
                      "value": "out"
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
    """.utf8)

  let manifest = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: data)
  let controls = manifest.pages[0].sections[0].controls

  #expect(manifest.pages[0].iconName == "square.grid.2x2")
  #expect(manifest.pages[0].sections[0].iconEmoji == "📚")
  #expect(controls[0].kind == .libraryList)
  #expect(controls[0].rowTemplate?.id == "{{id}}")
  #expect(controls[0].items[0].values["id"] == "hg38")
  #expect(controls[0].rowActions[0].command.arguments.contains("{{row.id}}"))
  #expect(controls[0].rowActions[0].command.optionalArguments == [["--label", "{{row.label}}"]])
  #expect(controls[0].rowActions[0].iconName == "checkmark.seal")
  #expect(controls[0].rowActions[0].iconOnly)
  #expect(controls[1].kind == .configEditor)
  #expect(controls[1].configFile?.path == "config/settings.toml")
  #expect(controls[1].configFile?.bootstrap?.mode == .createIfMissing)
  #expect(controls[1].settings[0].key == "output_dir")
}

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

private struct CopyingArchiveExtractor: BundleArchiveExtracting {
  func extractArchive(
    at sourceURL: URL,
    format: BundleArchiveFormat,
    to destinationURL: URL
  ) throws {
    try BundleSourceLoader().writeDemoBundle(to: destinationURL, overwrite: true)
  }
}

private func temporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("gui-for-cli-tests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}
