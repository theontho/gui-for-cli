import AppKit
import SwiftUI
import Testing

@MainActor
@Suite struct TerminalTextSyncTests {
  let style = TerminalTextStyle(fontSize: 12, textDirection: .leftToRight)

  @Test func appendsOnlyNewLinesAfterTheFirstRender() {
    let buffer = TerminalOutputBuffer(lines: ["a", "b"])
    let storage = NSTextStorage()
    let sync = TerminalTextSync()

    #expect(sync.apply(buffer, style: style, to: storage))
    #expect(storage.string == "a\nb")

    buffer.append(["", "d"])
    #expect(!sync.apply(buffer, style: style, to: storage))
    #expect(storage.string == buffer.text)
    #expect(!sync.apply(buffer, style: style, to: storage))
    #expect(storage.string == "a\nb\n\nd")
  }

  @Test func startsWithoutASeparatorWhenTheFirstLineIsEmpty() {
    let buffer = TerminalOutputBuffer()
    let storage = NSTextStorage()
    let sync = TerminalTextSync()
    sync.apply(buffer, style: style, to: storage)

    buffer.append(["", "x"])
    sync.apply(buffer, style: style, to: storage)

    #expect(storage.string == buffer.text)
  }

  @Test func rebuildsAfterTrimTabSwitchOrStyleChange() {
    let buffer = TerminalOutputBuffer(lineLimit: 10)
    let storage = NSTextStorage()
    let sync = TerminalTextSync()
    sync.apply(buffer, style: style, to: storage)

    buffer.append((0..<12).map(String.init))
    #expect(sync.apply(buffer, style: style, to: storage))
    #expect(storage.string == buffer.text)
    #expect(storage.string.hasPrefix("2\n"))

    let other = TerminalOutputBuffer(lines: ["other tab"])
    #expect(sync.apply(other, style: style, to: storage))
    #expect(storage.string == "other tab")

    let larger = TerminalTextStyle(fontSize: 16, textDirection: .leftToRight)
    #expect(sync.apply(other, style: larger, to: storage))
  }
}
