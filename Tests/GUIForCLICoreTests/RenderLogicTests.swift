import Foundation
import Testing

@testable import GUIForCLICore

@Test func commandRenderContextResolvesFieldsRowsConfigAndComputedFileState() throws {
  let temporaryFile = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .appendingPathExtension("bam")
  try "abc".write(to: temporaryFile, atomically: true, encoding: .utf8)
  let indexFile = URL(fileURLWithPath: "\(temporaryFile.path).bai")
  try Data().write(to: indexFile)
  defer { try? FileManager.default.removeItem(at: temporaryFile) }
  defer { try? FileManager.default.removeItem(at: indexFile) }

  let context = CommandRenderContext(
    fieldValues: ["sample": "NA12878", "input": temporaryFile.path],
    checkedOptions: ["flags": "a,b"],
    configValues: ["threads": "8"],
    rowValues: ["id": "row-1"],
    bundleRootPath: "/bundle",
    placeholderLabels: [
      "sample": "Sample",
      "input": "Input",
    ])

  #expect(context.value(for: "sample") == "NA12878")
  #expect(context.value(for: "row.id") == "row-1")
  #expect(context.value(for: "config.threads") == "8")
  #expect(context.value(for: "bundleRoot") == "/bundle")
  #expect(context.value(for: "input.exists") == "true")
  #expect(context.value(for: "input.pathExtension") == "bam")
  #expect(context.value(for: "input.fileSize") == "3")
  #expect(context.value(for: "input.fileSizeGB") == "0.00")
  #expect(context.value(for: "input.parentDir") == temporaryFile.deletingLastPathComponent().path)
  #expect(context.value(for: "input.isIndexed") == "true")
  #expect(context.value(for: "input.isSorted") == "true")
  #expect(context.value(for: "missing.exists") == "false")
  #expect(context.value(for: "missing.fileSize") == "")
  #expect(context.label(for: "row.sample") == "Sample")
  #expect(context.label(for: "config.input.fileSize") == "Input")
  #expect(context.interpolated("{{sample}}:{{config.threads}}") == "NA12878:8")
}

@Test func renderedCommandDropsOptionalArgumentGroupsWithMissingPlaceholders() {
  let command = CommandSpec(
    executable: "/bin/echo",
    arguments: ["{{name}}"],
    optionalArguments: [
      ["--present", "{{present}}"],
      ["--missing", "{{missing}}"],
    ])
  let context = CommandRenderContext(fieldValues: ["name": "Ada", "present": "yes"])

  let rendered = command.renderedCommand(resolving: context)

  #expect(rendered.executable == "/bin/echo")
  #expect(rendered.arguments == ["Ada", "--present", "yes"])
  #expect(rendered.displayCommand == "/bin/echo Ada --present yes")
  #expect(command.missingPlaceholders(resolving: context) == [])
}

@Test func actionConditionNumericComparisonsMatchContextValues() {
  let context = CommandRenderContext(fieldValues: ["size": "10", "limit": "8"])

  #expect(
    ActionConditionSpec(placeholder: "size", greaterThan: "{{limit}}")
      .matches(resolving: context))
  #expect(
    !ActionConditionSpec(placeholder: "size", lessThan: "{{limit}}")
      .matches(resolving: context))
}

@Test func manifestExtensionsDeriveStateAndHydrateListRows() throws {
  let control = ControlSpec(
    id: "references",
    label: "References",
    kind: .libraryList,
    columns: [
      ListColumnSpec(id: "code", title: "Code"),
      ListColumnSpec(id: "label", title: "Label"),
    ],
    rowTemplate: ListRowSpec(
      id: "ref-{{item.code}}",
      title: "{{item.label}}",
      values: ["code": "{{code}}", "label": "{{label}}"],
      status: "{{status}}",
      tags: [
        TagSpec(id: "tag-{{code}}", title: "{{tag}}", style: .success),
        TagSpec(id: "empty", title: "{{missing}}"),
      ],
      tooltip: "Use {{label}}"),
    items: [
      ListItemSpec(
        values: [
          "code": "GRCh38",
          "label": "Human",
          "status": "ready",
          "tag": "installed",
        ])
    ])
  let textControl = ControlSpec(id: "sample", label: "Sample", kind: .text, value: "NA12878")
  let checkboxControl = ControlSpec(
    id: "formats",
    label: "Formats",
    kind: .checkboxGroup,
    options: [
      ControlOption(id: "vcf", title: "VCF", selected: true),
      ControlOption(id: "bam", title: "BAM"),
    ])
  let configControl = ControlSpec(
    id: "settings",
    label: "Settings",
    kind: .configEditor,
    settings: [
      ConfigSettingSpec(id: "threads", key: "threads", label: "Threads", kind: .text, value: "8")
    ])
  let manifest = CLIBundleManifest(
    id: "example",
    displayName: "Example",
    summary: "Example bundle",
    iconName: "terminal",
    pages: [
      BundlePage(
        id: "home",
        title: "Home",
        summary: "Home page",
        sections: [
          PageSection(
            id: "main",
            controls: [textControl, checkboxControl, configControl, control])
        ])
    ])

  let row = try #require(control.hydratedRows.first)
  #expect(row.id == "ref-GRCh38")
  #expect(row.title == "Human")
  #expect(row.values == ["code": "GRCh38", "label": "Human"])
  #expect(row.status == "ready")
  #expect(row.tags == [TagSpec(id: "tag-GRCh38", title: "installed", style: .success)])
  #expect(row.tooltip == "Use Human")
  #expect(manifest.initialFieldValues == ["sample": "NA12878"])
  #expect(manifest.initialCheckedOptions == ["formats": ["vcf"]])
  #expect(manifest.initialConfigValues == ["settings.threads": "8"])
  #expect(manifest.statefulValueControls.map { $0.id } == ["sample"])
  #expect(manifest.checkboxControls.map { $0.id } == ["formats"])
  #expect(configControl.configValueKey(for: configControl.settings[0]) == "settings.threads")
}

@Test func dataSourcePayloadAliasesAndHelpersWork() throws {
  let data = try """
  {
    "items": [
      {"id": "row-1", "title": "Row 1"}
    ],
    "actions": [
      {"id": "open", "title": "Open", "command": {"executable": "echo"}}
    ],
    "values": {
      "answer": "42"
    }
  }
  """.data(using: .utf8).unwrap()
  let payload = try JSONDecoder().decode(DataSourcePayload.self, from: data)
  let dynamicData = DynamicControlData(payload: payload)

  #expect(payload.rows?.first?.id == "row-1")
  #expect(payload.rowActions?.first?.id == "open")
  #expect(payload.values == ["answer": "42"])
  #expect(dynamicData.rows == payload.rows)
  #expect(dynamicData.rowActions == payload.rowActions)
  let splitUTF8Data =
    Data(String(repeating: "a", count: 511).utf8) + Data("😀".utf8)
  #expect(!DataSourceRunner.outputPreview(splitUTF8Data).contains("<non-UTF-8 output>"))
  #expect(
    DataSourceRunner.outputPreview(Data(repeating: 65, count: 513)).hasSuffix("(output truncated)"))
  #expect(
    DataSourceRunner.interpolate(
      "{{name}}", context: CommandRenderContext(fieldValues: ["name": "Ada"])) == "Ada")
  #expect(DataSourceRunner.environmentKey("hello-world.1") == "HELLO_WORLD_1")
  let description = try #require(DataSourceError.unsupportedPlatform.errorDescription)
  #expect(description.localizedCaseInsensitiveContains("macOS"))
}

private enum OptionalUnwrapError: Error {
  case nilValue
}

private extension Optional {
  func unwrap() throws -> Wrapped {
    guard let self else { throw OptionalUnwrapError.nilValue }
    return self
  }
}
