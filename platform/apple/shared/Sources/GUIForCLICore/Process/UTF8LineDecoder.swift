import Foundation

/// Splits a byte stream into lines and decodes them as UTF-8.
///
/// Lines are split on the `\n` byte, which never occurs inside a multibyte UTF-8
/// sequence, so characters split across read boundaries decode correctly. Invalid
/// bytes become U+FFFD instead of dropping the chunk. A carriage return rewrites
/// the line the way a terminal would (progress bars keep only their last state).
public struct UTF8LineDecoder: Sendable {
  public static let defaultMaximumLineBytes = 64 * 1024

  private let maximumLineBytes: Int
  private var pending: [UInt8] = []

  public init(maximumLineBytes: Int = Self.defaultMaximumLineBytes) {
    self.maximumLineBytes = max(4, maximumLineBytes)
  }

  public mutating func append(_ bytes: some Sequence<UInt8>) -> [String] {
    pending.append(contentsOf: bytes)
    var lines: [String] = []
    var lineStart = 0
    while let newline = pending[lineStart...].firstIndex(of: 0x0A) {
      lines.append(Self.decodeLine(pending[lineStart..<newline]))
      lineStart = newline + 1
    }
    pending.removeFirst(lineStart)
    while pending.count > maximumLineBytes {
      var cut = maximumLineBytes
      while cut > 0, Self.isContinuationByte(pending[cut]) {
        cut -= 1
      }
      if cut == 0 {
        cut = maximumLineBytes
      }
      lines.append(Self.decodeLine(pending[..<cut]))
      pending.removeFirst(cut)
    }
    return lines
  }

  /// Emits the trailing partial line, if any.
  public mutating func finish() -> [String] {
    guard !pending.isEmpty else { return [] }
    defer { pending.removeAll() }
    return [Self.decodeLine(pending[...])]
  }

  private static func decodeLine(_ bytes: ArraySlice<UInt8>) -> String {
    var line = bytes
    if line.last == 0x0D {
      line.removeLast()
    }
    if let carriageReturn = line.lastIndex(of: 0x0D) {
      line = line[(carriageReturn + 1)...]
    }
    return String(decoding: line, as: UTF8.self)
  }

  private static func isContinuationByte(_ byte: UInt8) -> Bool {
    byte & 0b1100_0000 == 0b1000_0000
  }
}
