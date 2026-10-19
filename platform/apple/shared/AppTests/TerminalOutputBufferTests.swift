import Testing

@MainActor
@Suite struct TerminalOutputBufferTests {
  @Test func capsScrollbackAndReportsTrimsAsNewGeneration() {
    let buffer = TerminalOutputBuffer(lineLimit: 100)
    buffer.append((0..<105).map(String.init))
    #expect(buffer.lines.count == 105)
    #expect(buffer.generation == 0)

    buffer.append((105..<115).map(String.init))
    #expect(buffer.lines.count == 100)
    #expect(buffer.lines.first == "15")
    #expect(buffer.appendedLineCount == 115)
    #expect(buffer.generation == 1)
  }

  @Test func returnsOnlyLinesAppendedSinceAnObservedCount() {
    let buffer = TerminalOutputBuffer(lines: ["a", "b"])
    let seen = buffer.appendedLineCount
    buffer.append(["c", "d"])
    #expect(Array(buffer.lines(appendedAfter: seen)) == ["c", "d"])
    #expect(buffer.lines(appendedAfter: buffer.appendedLineCount).isEmpty)
    #expect(buffer.text == "a\nb\nc\nd")
  }
}
