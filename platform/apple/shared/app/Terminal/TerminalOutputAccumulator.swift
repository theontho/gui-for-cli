import Foundation

final class TerminalOutputAccumulator: @unchecked Sendable {
  private let lock = NSLock()
  private var bufferedText = ""
  private var hasScheduledFlush = false

  var isEmpty: Bool {
    lock.withLock { bufferedText.isEmpty }
  }

  @discardableResult
  func append(_ text: String) -> Bool {
    lock.withLock {
      bufferedText.append(text)
      guard !hasScheduledFlush else { return false }
      hasScheduledFlush = true
      return true
    }
  }

  func markScheduledFlushCompleted() {
    lock.withLock {
      hasScheduledFlush = false
    }
  }

  func clear() {
    lock.withLock {
      bufferedText = ""
      hasScheduledFlush = false
    }
  }

  func drain(flushingPartialLine: Bool) -> [String] {
    lock.withLock {
      guard !bufferedText.isEmpty else { return [] }

      let endsWithNewline = bufferedText.last?.isNewline == true
      let lines = bufferedText.split(whereSeparator: \.isNewline).map(String.init)

      if flushingPartialLine || endsWithNewline {
        bufferedText = ""
        return lines
      }

      guard let trailingFragment = lines.last else {
        return []
      }

      bufferedText = trailingFragment
      return Array(lines.dropLast())
    }
  }
}
