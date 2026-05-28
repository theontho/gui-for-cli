import Foundation
import Testing

@testable import GUIForCLICore

@Test func conformanceBundlePreservesSharedRuntimeSemanticsInSwift() throws {
  let loaded = try BundleSourceLoader().load(from: conformanceBundleURL(), localizationCode: "en")
  let manifest = loaded.manifest

  #expect(manifest.id == "conformance-basic")
  #expect(manifest.displayName == "Conformance Basic")
  #expect(manifest.summary == "Exercises common bundle runtime semantics.")
  #expect(manifest.textIcon == "🧪")
  #expect(manifest.sidebarIconStyle == .emoji)
  #expect(manifest.terminalTextDirection == .leftToRight)
  #expect(manifest.pages.map(\.id) == ["main"])
  #expect(manifest.pages[0].title == "Main")
  #expect(manifest.pages[0].sidebarGroup == "Main Group")
  #expect(manifest.setup.steps[0].label == "Install dependencies")
  #expect(
    manifest.exitCodeReference.first { $0.code == 7 }
      == ExitCodeReferenceEntry(
        code: 7,
        title: "Custom warning",
        summary: "A custom warning exit code.",
        severity: .warning))
  #expect(manifest.exitCodeReference.first { $0.code == 127 }?.title == "Command not found")

  let section = try #require(manifest.pages[0].sections.first)
  let input = try #require(section.controls.first { $0.id == "input_path" })
  let refs = try #require(section.controls.first { $0.id == "refs" })
  let settings = try #require(section.controls.first { $0.id == "settings" })
  let run = try #require(section.actions.first { $0.id == "run" })

  #expect(input.label == "Input BAM")
  #expect(input.value == "/tmp/input.bam")
  #expect(settings.configFile?.path == "{{bundleWorkspace}}/settings/config.toml")
  #expect(settings.configFile?.bootstrap?.mode == .createIfMissing)
  #expect(settings.settings[0].key == "output_dir")
  #expect(manifest.initialFieldValues["input_path"] == "/tmp/input.bam")
  #expect(manifest.initialConfigValues["settings.out_dir"] == "out")

  let rows = refs.hydratedRows
  #expect(rows.map(\.id) == ["hg38"])
  #expect(rows[0].title == "GRCh38")
  #expect(rows[0].values == ["code": "hs38", "status": "installed"])
  #expect(rows[0].status == "installed")
  #expect(rows[0].tags == [TagSpec(id: "recommended", title: "Recommended", style: .primary)])

  let context = CommandRenderContext(
    fieldValues: ["input_path": "/tmp/input.bam", "library.ready": "true"],
    configValues: ["out_dir": "out"],
    rowValues: ["id": rows[0].id, "code": "hs38", "status": "installed", "locked": "false"],
    bundleRootPath: conformanceBundleURL().path)

  #expect(run.visibleWhen[0].matches(resolving: context))
  #expect(!run.disabledWhen[0].matches(resolving: context))
  #expect(run.command.displayCommand(resolving: context) == "'tool' 'run' '/tmp/input.bam' 'out'")

  let rowAction = try #require(refs.rowActions.first)
  #expect(rowAction.visibleWhen[0].matches(resolving: context))
  #expect(!rowAction.disabledWhen[0].matches(resolving: context))
  #expect(
    rowAction.command.displayCommand(resolving: context)
      == "'tool' 'verify' 'hs38' '/tmp/input.bam'")
}

@Test func conformanceBundleAppliesRequestedLocalizationOverlaysInSwift() throws {
  let loaded = try BundleSourceLoader().load(from: conformanceBundleURL(), localizationCode: "es")

  #expect(loaded.localizationCode == "es")
  #expect(loaded.manifest.displayName == "Conformidad básica")
  #expect(loaded.manifest.pages[0].title == "Principal")
  #expect(loaded.manifest.pages[0].sections[0].actions[0].title == "Ejecutar flujo")
  #expect(loaded.manifest.summary == "Ejercita semánticas comunes de ejecución de paquetes.")
}

private func conformanceBundleURL() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../../../../../tests/conformance/basic-bundle", isDirectory: true)
    .standardizedFileURL
}
