import Testing

@testable import GUIForCLICore

@Suite("AccessibilityIdentifier")
struct AccessibilityIdentifierTests {
  @Test func pageNamespace() {
    #expect(AccessibilityIdentifier.page("info-bam") == "page.info-bam")
  }

  @Test func sectionNamespace() {
    #expect(AccessibilityIdentifier.section("inputs") == "section.inputs")
  }

  @Test func controlNamespace() {
    #expect(AccessibilityIdentifier.control("bam_path") == "control.bam_path")
  }

  @Test func actionNamespace() {
    #expect(AccessibilityIdentifier.action("realign") == "action.realign")
  }

  @Test func optionNamespace() {
    #expect(
      AccessibilityIdentifier.option(controlID: "ref", optionID: "hg38") == "option.ref.hg38")
  }

  @Test func chooserAndInfoDeriveFromControl() {
    #expect(AccessibilityIdentifier.chooser(controlID: "bam_path") == "control.bam_path.choose")
    #expect(AccessibilityIdentifier.info(controlID: "bam_path") == "control.bam_path.info")
  }

  @Test func identifiersAreASCIIAndStable() {
    let id = AccessibilityIdentifier.control("bam_path")
    #expect(id.allSatisfy { $0.isASCII })
  }
}
