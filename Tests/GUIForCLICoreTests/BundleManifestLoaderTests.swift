import Foundation
import Testing

@testable import GUIForCLICore

@Test func decodesDemoJSONManifest() throws {
  let data = Data(DemoBundleManifest.json.utf8)
  let manifest = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: data)

  #expect(manifest.id == "wgs-extract")
  #expect(manifest.displayName == "bundle.displayName")
  #expect(manifest.iconName == "point.3.connected.trianglepath.dotted")
  #expect(manifest.iconPath == "Assets/icon.png")
  #expect(manifest.iconEmoji == "🧬")
  #expect(manifest.sidebarIconStyle == .automatic)
  #expect(manifest.setup.steps.contains { $0.kind == .setupScript })
  #expect(manifest.setup.steps.contains { $0.kind == .pixiRun && $0.optional })
  #expect(
    manifest.pages.map(\.id) == [
      "workflow", "info-bam", "extract", "microarray", "ancestry", "vcf", "fastq",
      "pet-analysis", "library", "settings",
    ])
  #expect(manifest.pages.first { $0.id == "vcf" }?.sections.count == 4)
  #expect(
    manifest.pages.first { $0.id == "microarray" }?.sections[1].controls[0].options.count == 19)
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
      """.utf8))

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
  let manifestURL = directory.appendingPathComponent("manifest.json", isDirectory: false)
  try DemoBundleManifest.json.write(to: manifestURL, atomically: true, encoding: .utf8)

  let loaded = try BundleSourceLoader().load(from: directory)

  #expect(loaded.manifest.id == "wgs-extract")
  #expect(loaded.manifestURL.resolvingSymlinksInPath() == manifestURL.resolvingSymlinksInPath())
  #expect(loaded.isTemporary == false)
}

@Test func loadsNestedBundleFolder() throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let nested = directory.appendingPathComponent("WGSExtract.gui-cli", isDirectory: true)
  try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
  let manifestURL = nested.appendingPathComponent("manifest.json", isDirectory: false)
  try DemoBundleManifest.json.write(to: manifestURL, atomically: true, encoding: .utf8)

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
  #expect(FileManager.default.fileExists(atPath: manifestURL.path))
  #expect(
    FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("strings.toml", isDirectory: false).path))
  #expect(FileManager.default.fileExists(atPath: scriptURL.path))
  #expect(
    FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Assets/icon.png", isDirectory: false).path))

  let attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
  let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
  #expect(permissions.intValue & 0o111 != 0)
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

private struct CopyingArchiveExtractor: BundleArchiveExtracting {
  func extractArchive(
    at sourceURL: URL,
    format: BundleArchiveFormat,
    to destinationURL: URL
  ) throws {
    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    let manifestURL = destinationURL.appendingPathComponent("manifest.json", isDirectory: false)
    try DemoBundleManifest.json.write(to: manifestURL, atomically: true, encoding: .utf8)
  }
}

private func temporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("gui-for-cli-tests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}
