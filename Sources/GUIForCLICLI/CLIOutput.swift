import ArgumentParser
import Foundation
import GUIForCLICore

enum CLIOutput {
  static func line(_ message: String, quiet: Bool = false) {
    if !quiet { print(message) }
  }

  static func log(
    _ message: String, level: LogLevel, configuredLevel: LogLevel, quiet: Bool = false
  ) {
    guard level.severity >= configuredLevel.severity else { return }
    if quiet && level != .error { return }

    let stream = level == .error ? FileHandle.standardError : FileHandle.standardOutput
    if let data = "[\(level.rawValue)] \(message)\n".data(using: .utf8) {
      stream.write(data)
    }
  }
}
