import Foundation
import Testing

@testable import GUIForCLICore

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
  ).write(to: stringsDir.appendingPathComponent("strings.en.toml", isDirectory: false))
  try Data(
    """
    "language.name" = "Deutsch"
    "bundle.displayName" = "Deutsches Werkzeug"
    "pages.main.title" = "Deutsche Seite"
    """.utf8
  ).write(to: stringsDir.appendingPathComponent("strings.de.toml", isDirectory: false))

  let loaded = try BundleSourceLoader().load(from: directory, localizationCode: "de")

  #expect(loaded.localizationCode == "de")
  let optionCodes = loaded.localizationOptions.map(\.code)
  #expect(optionCodes.first == "en")
  #expect(optionCodes.contains("de"))
  #expect(loaded.manifest.displayName == "Deutsches Werkzeug")
  #expect(loaded.manifest.summary == "English summary.")
  #expect(loaded.manifest.pages[0].title == "Deutsche Seite")
  #expect(loaded.manifest.pages[0].summary == "Fallback summary.")
}
