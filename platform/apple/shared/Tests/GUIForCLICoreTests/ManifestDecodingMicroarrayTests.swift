import Testing

@testable import GUIForCLICore

@Test func decodesWGSExtractMicroarrayControls() throws {
  let manifest = try BundleSourceLoader().load(from: DemoBundle.wgsExtractResourceRootURL).manifest
  let microarrayFormatsControl = try #require(
    manifest.pages.first { $0.id == "microarray" }?
      .sections.first { $0.id == "microarray-formats" }?
      .controls.first { $0.id == "microarray_formats" })

  #expect(
    microarrayFormatsControl.options.map(\.id) == [
      "all", "23andme_v3", "23andme_v4", "23andme_v5", "23andme_v35", "ancestry_v1",
      "ancestry_v2", "ftdna_v2", "ftdna_v3", "ldna_v1", "ldna_v2", "myheritage_v1",
      "myheritage_v2",
    ])

  let microarrayActions = try #require(
    manifest.pages.first { $0.id == "microarray" }?.sections.first {
      $0.id == "microarray-formats"
    }?.actions)
  let microarrayAction = try #require(
    microarrayActions.first { $0.id == "microarray-generate" })
  #expect(microarrayAction.command.executable == "{{bundleRoot}}/scripts/run-wgsextract.sh")
  #expect(
    Array(microarrayAction.command.arguments.prefix(3)) == [
      "microarray", "--input", "{{bam_path}}",
    ])
  #expect(Array(microarrayAction.command.arguments[3...4]) == ["--ref", "{{ref_fasta}}"])

  let microarrayReferenceControl = try #require(
    manifest.pages.first { $0.id == "microarray" }?
      .sections.first { $0.id == "microarray-inputs" }?
      .controls.first { $0.id == "ref_fasta" })
  #expect(microarrayReferenceControl.kind == .dropdown)
  #expect(microarrayReferenceControl.dataSource?.arguments == ["options", "{{ref_path}}"])
}
