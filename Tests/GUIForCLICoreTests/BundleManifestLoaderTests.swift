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
  #expect(manifest.terminalTextDirection == .leftToRight)
  #expect(manifest.setup.steps.contains { $0.kind == .setupScript })
  #expect(manifest.setup.steps.contains { $0.kind == .pixiRun && $0.optional })
  #expect(manifest.exitCodeReference.first { $0.code == 127 }?.title == "Command not found")
  #expect(manifest.exitCodeReference.first { $0.code == 130 }?.severity == .warning)
  #expect(
    rawManifest.pageFiles == [
      "fastq.json", "info-bam.json", "vcf.json", "extract.json", "microarray.json",
      "ancestry.json", "annotate.json", "library.json", "settings.json",
    ])
  #expect(
    manifest.pages.map(\.id) == [
      "fastq", "info-bam", "vcf", "extract", "microarray", "ancestry", "annotate", "library",
      "settings",
    ])
  #expect(
    manifest.pages.filter { $0.sidebarGroup == "Convert" }.map(\.id) == [
      "fastq", "info-bam", "vcf",
    ])
  #expect(
    manifest.pages.filter { $0.sidebarGroup == "Analyze" }.map(\.id) == [
      "extract", "microarray", "ancestry", "annotate",
    ])
  #expect(manifest.pages.first { $0.id == "library" }?.iconName == "books.vertical")
  #expect(
    manifest.pages.first { $0.id == "fastq" }?.sections.contains { $0.id == "pet-inputs" } == true)
  #expect(
    manifest.pages.first { $0.id == "vcf" }?.sections.map(\.id) == [
      "vcf-inputs", "variant-calling",
    ])
  let variantCallingActions = try #require(
    manifest.pages.first { $0.id == "vcf" }?.sections.first { $0.id == "variant-calling" }?
      .actions)
  #expect(
    variantCallingActions.first { $0.id == "vcf-cnv" }?.command.optionalArguments.contains([
      "--map", "{{vcf_mappability_map}}",
    ])
      == true)
  #expect(
    manifest.pages.first { $0.id == "annotate" }?.sections.map(\.id) == [
      "annotate-inputs", "vcf-annotation", "trio-analysis", "vep-analysis",
    ])
  #expect(
    manifest.pages.first { $0.id == "microarray" }?.sections[1].controls[0].options.count == 19)
  #expect(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "genome-management" }?
      .controls.first?.kind == .libraryList)
  let databaseToolsSection = try #require(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "databases-tools" })
  #expect(databaseToolsSection.dataSource?.path == "scripts/library-state.sh")
  #expect(
    databaseToolsSection.actions.first { $0.id == "gene-map-delete" }?.visibleWhen.first?
      .placeholder == "library.geneMapInstalled")
  #expect(
    databaseToolsSection.actions.first { $0.id == "library-bootstrapped" }?.disabledWhen.first?
      .placeholder == "library.isBootstrapped")
  #expect(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "genome-management" }?
      .controls.first?.dataSource?.path == "scripts/list-reference-genomes.sh")
  let libraryList = try #require(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "genome-management" }?
      .controls.first)
  #expect(libraryList.rowTemplate?.values["code"] == "{{code}}")
  #expect(
    libraryList.rowActions.first { $0.id == "ref-download" }?.command.arguments.contains(
      "{{row.code}}") == true)
  #expect(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "genome-management" }?
      .controls.first?.items.isEmpty == true)
  #expect(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "genome-management" }?
      .controls.first?.rowTemplate?.id == "{{id}}")
  #expect(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "genome-management" }?
      .controls.first?.rowActions.first { $0.id == "ref-delete" }?.confirm?.requiredText
      == "{{row.final}}")
  #expect(
    Array(
      databaseToolsSection.actions.first { $0.id == "vep-download" }?.command.arguments.prefix(2)
        ?? [])
      == ["vep", "download"])
  #expect(
    Array(
      databaseToolsSection.actions.first { $0.id == "vep-verify" }?.command.arguments.prefix(2)
        ?? [])
      == ["vep", "verify"])
  #expect(databaseToolsSection.actions.first { $0.id == "gene-map-delete" }?.confirm != nil)
  #expect(
    manifest.pages.first { $0.id == "info-bam" }?.sections.first { $0.id == "info-commands" }?
      .actions.first?.id == "basic-info")
  let bamCommands = try #require(
    manifest.pages.first { $0.id == "info-bam" }?.sections.first { $0.id == "bam-commands" }?
      .actions)
  #expect(
    bamCommands.first { $0.id == "bam-unalign" }?.command.executable
      == "{{bundleRoot}}/scripts/unalign-to-fastq.sh")
  #expect(
    bamCommands.first { $0.id == "repair-ftdna-bam" }?.command.executable
      == "{{bundleRoot}}/scripts/repair-ftdna-bam.sh")
  let extractActions = try #require(
    manifest.pages.first { $0.id == "extract" }?.sections.first { $0.id == "extract-inputs" }?
      .actions)
  #expect(
    extractActions.first { $0.id == "custom" }?.command.arguments.contains("{{extract_region}}")
      == true)
  let vcfPage = try #require(manifest.pages.first { $0.id == "annotate" })
  let vcfAnnotationActions = try #require(
    vcfPage.sections.first { $0.id == "vcf-annotation" }?.actions)
  #expect(
    vcfAnnotationActions.filter { $0.id != "vcf-repair-ftdna" }.allSatisfy {
      $0.command.arguments.contains("--vcf-input")
    })
  #expect(
    vcfAnnotationActions.first { $0.id == "vcf-annotate" }?.command.optionalArguments.contains([
      "--ann-vcf", "{{vcf_ann_vcf}}",
    ])
      == true)
  #expect(
    vcfAnnotationActions.first { $0.id == "vcf-qc" }?
      .command.arguments.contains("--vcf-input") == true)
  #expect(
    vcfAnnotationActions.first { $0.id == "vcf-filter" }?.visibleWhen.first?.equals == "false")
  #expect(
    vcfAnnotationActions.first { $0.id == "vcf-filter-gap-aware" }?.visibleWhen.first?.equals
      == "true")
  #expect(
    vcfAnnotationActions.first { $0.id == "vcf-filter-gap-aware" }?.command.arguments.contains(
      "--exclude-near-gaps") == true)
  #expect(
    vcfAnnotationActions.first { $0.id == "vcf-repair-ftdna" }?.command.executable
      == "{{bundleRoot}}/scripts/repair-ftdna-vcf.sh")
  #expect(
    manifest.pages.first { $0.id == "fastq" }?.sections.first { $0.id == "pet-inputs" }?
      .actions.first { $0.id == "pet-align" }?.command.arguments.contains("--ref") == true)
  let ancestryActions = try #require(
    manifest.pages.first { $0.id == "ancestry" }?.sections.first { $0.id == "ancestry-inputs" }?
      .actions)
  #expect(
    ancestryActions.first { $0.id == "run-yleaf" }?.command.arguments.contains("{{yleaf_path}}")
      == true)
  #expect(
    ancestryActions.first { $0.id == "run-haplogrep" }?.command.arguments.contains(
      "{{haplogrep_path}}") == true)
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
  #expect(settingsControl.settings.first { $0.id == "ref_fasta" }?.kind == .dropdown)
  #expect(
    settingsControl.settings.first { $0.id == "ref_fasta" }?.dataSource?.arguments
      == ["options", "{{ref_path}}"])
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
  #expect(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "genome-management" }?
      .controls.first?.rowActions.first { $0.id == "ref-delete" }?.confirm?.confirmButtonTitle
      == "Delete")
  #expect(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "databases-tools" }?
      .actions.first { $0.id == "gene-map-delete" }?.title == "Delete Gene Map")
  #expect(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "databases-tools" }?
      .actions.first { $0.id == "library-bootstrapped" }?.title == "Library Bootstrapped")
}

@Test func demoBundleLoadsTranslatedStringTables() throws {
  let loader = BundleSourceLoader()
  let german = try loader.load(from: DemoBundle.wgsExtractResourceRootURL, localizationCode: "de")
  let farsi = try loader.load(from: DemoBundle.wgsExtractResourceRootURL, localizationCode: "fa")
  let chinese = try loader.load(
    from: DemoBundle.wgsExtractResourceRootURL,
    localizationCode: "zh-Hans")

  #expect(
    Set(german.localizationOptions.map(\.code)).isSuperset(of: ["en", "de", "fa", "zh-Hans"]))
  #expect(german.localizationLabels.layoutDirection == .leftToRight)
  #expect(german.localizationLabels.languagePickerLabel == "Sprache")
  #expect(german.localizationLabels.terminalMainTabTitle == "Hauptprotokoll")
  #expect(german.localizationLabels.chooseButtonTitle == "Auswählen...")
  #expect(german.manifest.pages.first { $0.id == "settings" }?.title == "Einstellungen")
  #expect(german.manifest.pages.first { $0.id == "microarray" }?.title == "Mikroarray")
  #expect(
    german.manifest.pages.first { $0.id == "microarray" }?.sections[1].controls[0].options.first?
      .title == "Kombinierte ALLE SNPs (GEDMATCH)")
  #expect(
    german.manifest.pages.first { $0.id == "fastq" }?.sections[0].controls.first {
      $0.id == "fastq_r2"
    }?.label == "FASTQ R2 (wahlweise)")
  #expect(
    german.manifest.pages.filter { $0.sidebarGroup == "Konvertieren" }.map(\.id) == [
      "fastq", "info-bam", "vcf",
    ])
  #expect(german.localizationLabels.libraryStatusLabels["installed"] == "Installiert")
  #expect(german.localizationLabels.libraryTagLabels["recommended"] == "Empfohlen")
  #expect(farsi.localizationLabels.layoutDirection == .rightToLeft)
  #expect(farsi.localizationLabels.languagePickerLabel == "زبان")
  #expect(farsi.localizationLabels.terminalMainTabTitle == "اصلی")
  #expect(farsi.localizationLabels.chooseButtonTitle == "انتخاب...")
  #expect(farsi.manifest.pages.first { $0.id == "settings" }?.title == "تنظیمات")
  #expect(farsi.manifest.pages.first { $0.id == "microarray" }?.title == "میکروآرایه")
  #expect(chinese.localizationLabels.languagePickerLabel == "语言")
  #expect(chinese.manifest.pages.first { $0.id == "settings" }?.title == "设置")
  #expect(chinese.manifest.pages.first { $0.id == "microarray" }?.title == "微阵列")
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

@Test func bundleLoaderAppliesSelectedLocalizationWithFallback() throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let pages = directory.appendingPathComponent("pages", isDirectory: true)
  try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
  try Data(
    """
    {
      "id": "localized-bundle",
      "displayName": "bundle.displayName",
      "summary": "bundle.summary",
      "pages": ["main.json"]
    }
    """.utf8
  ).write(to: directory.appendingPathComponent("manifest.json", isDirectory: false))
  try Data(
    """
    {
      "id": "main",
      "title": "pages.main.title",
      "summary": "pages.main.summary",
      "sections": [
        {
          "id": "inputs"
        }
      ]
    }
    """.utf8
  ).write(to: pages.appendingPathComponent("main.json", isDirectory: false))
  let stringsDir = directory.appendingPathComponent("strings", isDirectory: true)
  try FileManager.default.createDirectory(at: stringsDir, withIntermediateDirectories: true)
  try Data(
    """
    "language.name" = "English"
    "bundle.displayName" = "English Tool"
    "bundle.summary" = "English summary."
    "pages.main.title" = "English Page"
    "pages.main.summary" = "Fallback summary."
    """.utf8
  ).write(to: stringsDir.appendingPathComponent("strings.toml", isDirectory: false))
  try Data(
    """
    "language.name" = "Deutsch"
    "bundle.displayName" = "Deutsches Werkzeug"
    "pages.main.title" = "Deutsche Seite"
    """.utf8
  ).write(to: stringsDir.appendingPathComponent("strings.de.toml", isDirectory: false))

  let loaded = try BundleSourceLoader().load(from: directory, localizationCode: "de")

  #expect(loaded.localizationCode == "de")
  #expect(loaded.localizationOptions.map(\.code) == ["en", "de"])
  #expect(loaded.manifest.displayName == "Deutsches Werkzeug")
  #expect(loaded.manifest.summary == "English summary.")
  #expect(loaded.manifest.pages[0].title == "Deutsche Seite")
  #expect(loaded.manifest.pages[0].summary == "Fallback summary.")
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

  let unsafeDataSource = Data(
    """
    {
      "id": "unsafe-data-source",
      "displayName": "Unsafe Data Source",
      "summary": "Bad data source.",
      "pages": [
        {
          "id":"main",
          "title":"Main",
          "summary":"Main page.",
          "sections":[
            {
              "id":"main-section",
              "controls":[
                {
                  "id":"refs",
                  "label":"Refs",
                  "kind":"dropdown",
                  "dataSource":{"path":"../list.sh"}
                }
              ]
            }
          ]
        }
      ]
    }
    """.utf8)
  #expect(
    throws: BundleValidationError.invalidRelativePath(
      path: "pages.main.sections.main-section.controls.refs.dataSource.path", value: "../list.sh")
  ) {
    _ = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: unsafeDataSource)
  }
}

@Test func rejectsTemplatedDataSourcePaths() throws {
  let unsafeDataSource = Data(
    """
    {
      "id": "unsafe-data-source-template",
      "displayName": "Unsafe Data Source Template",
      "summary": "Bad data source.",
      "pages": [
        {
          "id":"main",
          "title":"Main",
          "summary":"Main page.",
          "sections":[
            {
              "id":"main-section",
              "controls":[
                {
                  "id":"refs",
                  "label":"Refs",
                  "kind":"dropdown",
                  "dataSource":{"path":"{{home}}/list.sh"}
                }
              ]
            }
          ]
        }
      ]
    }
    """.utf8)
  #expect(
    throws: BundleValidationError.invalidRelativePath(
      path: "pages.main.sections.main-section.controls.refs.dataSource.path",
      value: "{{home}}/list.sh")
  ) {
    _ = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: unsafeDataSource)
  }

  let unsafeWorkingDirectory = Data(
    """
    {
      "id": "unsafe-data-source-working-directory",
      "displayName": "Unsafe Data Source Working Directory",
      "summary": "Bad data source.",
      "pages": [
        {
          "id":"main",
          "title":"Main",
          "summary":"Main page.",
          "sections":[
            {
              "id":"main-section",
              "controls":[
                {
                  "id":"refs",
                  "label":"Refs",
                  "kind":"dropdown",
                  "dataSource":{"path":"scripts/list.sh","workingDirectory":"~/scripts"}
                }
              ]
            }
          ]
        }
      ]
    }
    """.utf8)
  #expect(
    throws: BundleValidationError.invalidRelativePath(
      path: "pages.main.sections.main-section.controls.refs.dataSource.workingDirectory",
      value: "~/scripts")
  ) {
    _ = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: unsafeWorkingDirectory)
  }
}

@Test func acceptsNumericConditionOperators() throws {
  let payload = Data(
    """
    {
      "id": "numeric-conditions",
      "displayName": "Numeric Conditions",
      "summary": "Tests greaterThan support.",
      "pages": [
        {
          "id": "main",
          "title": "Main",
          "summary": "Main page.",
          "sections": [
            {
              "id": "main-section",
              "actions": [
                {
                  "id": "act",
                  "title": "Act",
                  "visibleWhen": [
                    {"placeholder": "bam_path.fileSizeGB", "greaterThan": "0.5"},
                    {"placeholder": "free_space_gb", "greaterThanOrEqual": "100"}
                  ],
                  "precheck": {
                    "diskSpaceGB": "{{bam_path.fileSizeGB}} * 6",
                    "diskSpacePath": "{{out_dir}}"
                  },
                  "command": {"executable": "tool", "arguments": ["go"]}
                }
              ]
            }
          ]
        }
      ]
    }
    """.utf8)
  let manifest = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: payload)
  let action = manifest.pages[0].sections[0].actions[0]
  #expect(action.visibleWhen[0].greaterThan == "0.5")
  #expect(action.visibleWhen[1].greaterThanOrEqual == "100")
  #expect(action.precheck?.diskSpaceGB == "{{bam_path.fileSizeGB}} * 6")
  #expect(action.precheck?.diskSpacePath == "{{out_dir}}")
}

@Test func rejectsVisibleWhenWithoutConditionOperator() throws {
  let invalidCondition = Data(
    """
    {
      "id": "invalid-visible-when",
      "displayName": "Invalid Visible When",
      "summary": "Bad condition.",
      "pages": [
        {
          "id":"main",
          "title":"Main",
          "summary":"Main page.",
          "sections":[
            {
              "id":"main-section",
              "controls":[
                {
                  "id":"refs",
                  "label":"Refs",
                  "kind":"libraryList",
                  "rowActions":[
                    {
                      "id":"verify",
                      "title":"Verify",
                      "visibleWhen":[{"placeholder":"row.status"}],
                      "command":{"executable":"tool","arguments":["verify"]}
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
  #expect(
    throws: BundleValidationError.emptyField(
      path:
        "pages.main.sections.main-section.controls.refs.rowActions.verify.visibleWhen.0")
  ) {
    _ = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: invalidCondition)
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
  let dataSourceScriptURL = directory.appendingPathComponent(
    "scripts/list-reference-genomes.sh", isDirectory: false)
  let deleteReferenceScriptURL = directory.appendingPathComponent(
    "scripts/delete-reference-genome.sh", isDirectory: false)
  #expect(FileManager.default.fileExists(atPath: manifestURL.path))
  #expect(
    FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("strings/strings.toml", isDirectory: false).path))
  #expect(FileManager.default.fileExists(atPath: scriptURL.path))
  #expect(FileManager.default.fileExists(atPath: bootstrapScriptURL.path))
  #expect(FileManager.default.fileExists(atPath: runScriptURL.path))
  #expect(FileManager.default.fileExists(atPath: dataSourceScriptURL.path))
  #expect(FileManager.default.fileExists(atPath: deleteReferenceScriptURL.path))
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
  let dataSourceScriptAttributes = try FileManager.default.attributesOfItem(
    atPath: dataSourceScriptURL.path)
  let dataSourceScriptPermissions = try #require(
    dataSourceScriptAttributes[.posixPermissions] as? NSNumber)
  #expect(dataSourceScriptPermissions.intValue & 0o111 != 0)
  let deleteReferenceScriptAttributes = try FileManager.default.attributesOfItem(
    atPath: deleteReferenceScriptURL.path)
  let deleteReferenceScriptPermissions = try #require(
    deleteReferenceScriptAttributes[.posixPermissions] as? NSNumber)
  #expect(deleteReferenceScriptPermissions.intValue & 0o111 != 0)
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
                  "dataSource": {
                    "path": "scripts/list-refs.sh",
                    "arguments": ["items", "{{ref_path}}"],
                    "environment": {"REF_LIBRARY": "{{ref_path}}"},
                    "workingDirectory": "scripts"
                  },
                  "columns": [
                    { "id": "name", "title": "Name" },
                    { "id": "status", "title": "Status" }
                  ],
                  "rowTemplate": {
                    "id": "{{id}}",
                    "title": "{{name}}",
                    "status": "{{status}}",
                    "values": { "status": "{{status}}" },
                    "tags": [
                      { "id": "recommended", "title": "{{recommended}}", "style": "primary" }
                    ]
                  },
                  "items": [
                    { "id": "hg38", "name": "HG38", "status": "installed", "recommended": "Recommended" }
                  ],
                  "rowActions": [
                    {
                      "id": "verify",
                      "title": "Verify",
                      "iconName": "checkmark.seal",
                      "iconOnly": true,
                      "visibleWhen": [
                        { "placeholder": "row.status", "in": ["installed", "unindexed"] }
                      ],
                      "disabledWhen": [
                        { "placeholder": "row.locked", "equals": "true" }
                      ],
                      "disabledTooltip": "This row is locked.",
                      "confirm": {
                        "title": "Verify {{row.id}}?",
                        "message": "This will inspect {{row.id}}.",
                        "confirmButtonTitle": "Verify",
                        "cancelButtonTitle": "Cancel",
                        "requiredText": "{{row.id}}",
                        "prompt": "Type {{row.id}} to continue."
                      },
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
                      "kind": "dropdown",
                      "value": "out",
                      "dataSource": {
                        "path": "scripts/list-outputs.sh",
                        "arguments": ["{{output_dir}}"]
                      }
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
  #expect(controls[0].dataSource?.path == "scripts/list-refs.sh")
  #expect(controls[0].dataSource?.workingDirectory == "scripts")
  #expect(controls[0].dataSource?.environment["REF_LIBRARY"] == "{{ref_path}}")
  #expect(controls[0].rowTemplate?.id == "{{id}}")
  #expect(controls[0].rowTemplate?.tags[0].style == .primary)
  #expect(controls[0].items[0].values["id"] == "hg38")
  #expect(controls[0].rowActions[0].command.arguments.contains("{{row.id}}"))
  #expect(controls[0].rowActions[0].command.optionalArguments == [["--label", "{{row.label}}"]])
  #expect(controls[0].rowActions[0].iconName == "checkmark.seal")
  #expect(controls[0].rowActions[0].iconOnly)
  #expect(controls[0].rowActions[0].visibleWhen[0].placeholder == "row.status")
  #expect(controls[0].rowActions[0].visibleWhen[0].inValues == ["installed", "unindexed"])
  #expect(controls[0].rowActions[0].disabledWhen[0].placeholder == "row.locked")
  #expect(controls[0].rowActions[0].disabledWhen[0].equals == "true")
  #expect(controls[0].rowActions[0].disabledTooltip == "This row is locked.")
  #expect(controls[0].rowActions[0].confirm?.title == "Verify {{row.id}}?")
  #expect(controls[0].rowActions[0].confirm?.requiredText == "{{row.id}}")
  #expect(controls[1].kind == .configEditor)
  #expect(controls[1].configFile?.path == "config/settings.toml")
  #expect(controls[1].configFile?.bootstrap?.mode == .createIfMissing)
  #expect(controls[1].settings[0].key == "output_dir")
  #expect(controls[1].settings[0].dataSource?.path == "scripts/list-outputs.sh")
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
