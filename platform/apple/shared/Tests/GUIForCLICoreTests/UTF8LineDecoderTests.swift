import Foundation
import Testing

@testable import GUIForCLICore

@Suite struct UTF8LineDecoderTests {
  @Test func decodesMultibyteCharactersSplitAcrossChunks() {
    var decoder = UTF8LineDecoder()
    let bytes = Array("héllo 日本\n".utf8)
    var lines: [String] = []
    for byte in bytes {
      lines += decoder.append([byte])
    }
    #expect(lines == ["héllo 日本"])
  }

  @Test func holdsPartialLinesUntilNewlineOrFinish() {
    var decoder = UTF8LineDecoder()
    #expect(decoder.append(Array("first\nsec".utf8)) == ["first"])
    #expect(decoder.append(Array("ond\nthird".utf8)) == ["second"])
    #expect(decoder.finish() == ["third"])
    #expect(decoder.finish().isEmpty)
  }

  @Test func handlesCRLFAndCarriageReturnOverwrites() {
    var decoder = UTF8LineDecoder()
    let lines = decoder.append(Array("dos\r\n10%\r50%\r100%\ndone\n".utf8))
    #expect(lines == ["dos", "100%", "done"])
  }

  @Test func replacesInvalidBytesInsteadOfDroppingOutput() {
    var decoder = UTF8LineDecoder()
    let lines = decoder.append([0x61, 0xFF, 0x62, 0x0A])
    #expect(lines == ["a\u{FFFD}b"])
  }

  @Test func splitsOverlongLinesOnCharacterBoundaries() {
    var decoder = UTF8LineDecoder(maximumLineBytes: 5)
    // "ééé" is 6 bytes; the cut must not land inside the third "é".
    let lines = decoder.append(Array("ééé".utf8))
    #expect(lines == ["éé"])
    #expect(decoder.finish() == ["é"])
  }
}
