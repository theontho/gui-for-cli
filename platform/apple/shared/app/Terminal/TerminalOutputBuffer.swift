import Foundation
import Observation

/// Capped scrollback for one terminal tab. Views render it incrementally: lines
/// appended since `appendedLineCount` was last seen are new, and a `generation`
/// change (trim or replace) means the visible text must be rebuilt.
@MainActor
@Observable
final class TerminalOutputBuffer {
  static let defaultLineLimit = 10_000

  let lineLimit: Int
  private(set) var lines: [String]
  /// Total lines ever appended, including ones trimmed away.
  private(set) var appendedLineCount: Int
  /// Bumped whenever existing lines are removed.
  private(set) var generation = 0

  init(lines: [String] = [], lineLimit: Int = TerminalOutputBuffer.defaultLineLimit) {
    self.lineLimit = max(1, lineLimit)
    self.lines = Array(lines.suffix(self.lineLimit))
    appendedLineCount = lines.count
  }

  var text: String {
    lines.joined(separator: "\n")
  }

  /// Lines appended after `count` (a previously observed `appendedLineCount`)
  /// that are still in the buffer.
  func lines(appendedAfter count: Int) -> ArraySlice<String> {
    let newCount = min(max(appendedLineCount - count, 0), lines.count)
    return lines.suffix(newCount)
  }

  func append(_ newLines: [String]) {
    guard !newLines.isEmpty else { return }
    lines.append(contentsOf: newLines)
    appendedLineCount += newLines.count
    // Trim in batches so trimming (and the view rebuild it triggers) is rare.
    if lines.count > lineLimit + lineLimit / 10 {
      lines.removeFirst(lines.count - lineLimit)
      generation += 1
    }
  }
}
