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
  #expect(manifest.iconName == "fasta")
  #expect(manifest.iconPath == "Assets/icon.png")
  #expect(manifest.textIcon == "🧬")
  #expect(manifest.sidebarIconStyle == .automatic)
  #expect(manifest.terminalTextDirection == .leftToRight)
  #expect(manifest.setup.steps.contains { $0.kind == .setupScript })
  #expect(manifest.setup.steps.contains { $0.id == "wgsextract-cli" && $0.kind == .pathTool })
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
  #expect(manifest.pages.first { $0.id == "library" }?.iconName == "library")
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
  #expect(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "library-paths" }?
      .controls.contains { $0.id == "genome_library" && $0.kind == .path } == true)
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
      .controls.first?.dataSource?.path == "scripts/list-reference-genomes.py")
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
  let testGenomeSection = try #require(
    manifest.pages.first { $0.id == "library" }?.sections.first { $0.id == "test-genome-data" })
  #expect(testGenomeSection.dataSource?.path == "scripts/test-genome-library.py")
  #expect(testGenomeSection.dataSource?.arguments == ["state", "{{genome_library}}"])
  #expect(
    testGenomeSection.actions.first { $0.id == "test-genome-download" }?.command.arguments
      == ["download", "{{genome_library}}"])
  #expect(testGenomeSection.actions.first { $0.id == "test-genome-delete" }?.confirm != nil)
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
  #expect(settingsControl.configFile?.bootstrap?.mode == .mergeMissing)
  #expect(
    settingsControl.configFile?.bootstrap?.script?.path
      == "scripts/bootstrap-wgsextract-config.sh")
  #expect(settingsControl.settings.first { $0.id == "ref_path" }?.key == "reference_library")
  #expect(settingsControl.settings.first { $0.id == "genome_library" }?.key == "genome_library")
  #expect(settingsControl.settings.first { $0.id == "ref_fasta" }?.kind == .dropdown)
  #expect(
    settingsControl.settings.first { $0.id == "ref_fasta" }?.dataSource?.arguments
      == ["options", "{{ref_path}}"])
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
@Test func decodesTextIconFallback() throws {
  let data = Data(
    """
    {
      "id": "text-icon",
      "displayName": "Text Icon",
      "summary": "Uses generated text-icon artwork.",
      "textIcon": "工",
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

  #expect(manifest.textIcon == "工")
  #expect(manifest.iconName == "terminal")
}

@Test func validatesTextIconLength() throws {
  let manifest = CLIBundleManifest(
    id: "text-icon-length",
    displayName: "Text Icon Length",
    summary: "Rejects long text icons.",
    iconName: "terminal",
    textIcon: "ABC",
    pages: [
      BundlePage(
        id: "main",
        title: "Main",
        summary: "Main page.",
        sections: [PageSection(id: "main-section")])
    ])

  #expect(throws: BundleValidationError.invalidTextIcon(path: "textIcon", value: "ABC")) {
    try manifest.validate()
  }
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
              "textIcon": "📚",
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
  #expect(manifest.pages[0].sections[0].textIcon == "📚")
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
