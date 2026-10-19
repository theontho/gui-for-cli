import Foundation

/// Mirrors terminal lines into a log file (set via `GUI_FOR_CLI_TERMINAL_LOG_FILE`)
/// on a background queue.
final class TerminalLogFileWriter: Sendable {
  static let environmentKey = "GUI_FOR_CLI_TERMINAL_LOG_FILE"

  private let url: URL
  private let queue = DispatchQueue(label: "dev.guiforcli.terminal-log-file-writer")

  init(url: URL) {
    self.url = url
  }

  static func fromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> TerminalLogFileWriter? {
    guard let path = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !path.isEmpty
    else {
      return nil
    }
    return TerminalLogFileWriter(url: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
  }

  func append(_ text: String) {
    let entry = "[\(Date().formatted(.iso8601))] \(text)\n"
    queue.async { [url] in
      Self.write(entry, to: url)
    }
  }

  private static func write(_ entry: String, to url: URL) {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
      }
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: Data(entry.utf8))
    } catch {
      fputs("terminal log write failed: \(error.localizedDescription)\n", stderr)
    }
  }
}
