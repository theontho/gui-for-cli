import Foundation
import Testing

@testable import GUIForCLICore

@Test func commandRenderContextResolvesFieldsRowsConfigAndComputedFileState() throws {
  let temporaryFile = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .appendingPathExtension("bam")
  try "abc".write(to: temporaryFile, atomically: true, encoding: .utf8)
  defer { try? FileManager.default.removeItem(at: temporaryFile) }

  let context = CommandRenderContext(
    fieldValues: ["sample": "NA12878", "input": temporaryFile.path],
    checkedOptions: ["flags": "a,b"],
    configValues: ["threads": "8"],
    rowValues: ["id": "row-1"],
    bundleRootPath: "/bundle")

  #expect(context.value(for: "sample") == "NA12878")
  #expect(context.value(for: "row.id") == "row-1")
  #expect(context.value(for: "config.threads") == "8")
  #expect(context.value(for: "bundleRoot") == "/bundle")
  #expect(context.value(for: "input.exists") == "true")
  #expect(context.value(for: "input.pathExtension") == "bam")
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
