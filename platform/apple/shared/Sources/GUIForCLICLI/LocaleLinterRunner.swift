import ArgumentParser
import Foundation
import GUIForCLICore

enum LocaleLinterRunner {
  struct Result {
    var errors: Int
    var warnings: Int
  }

  static func run(bundleRoot: URL, strict: Bool, quiet: Bool) throws -> Result {
    let scriptURL = scriptURL(for: bundleRoot)
    guard let scriptURL, FileManager.default.fileExists(atPath: scriptURL.path) else {
      // Linter unavailable — treat as a no-op rather than a failure.
      if !quiet {
        CLIOutput.line("  (locale linter not found; skipping)", quiet: false)
      }
      return Result(errors: 0, warnings: 0)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    var arguments = ["python3", scriptURL.path]
    if strict { arguments.append("--strict") }
    arguments.append(bundleRoot.path)
    process.arguments = arguments
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = stdout
    try process.run()
    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    let combined = String(data: outData, encoding: .utf8) ?? ""
    if !quiet {
      let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        CLIOutput.line(trimmed, quiet: false)
      }
    }
    return result(from: combined, terminationStatus: process.terminationStatus)
  }

  static func result(from combinedOutput: String, terminationStatus: Int32) -> Result {
    let errors = combinedOutput.matchCount(of: ", [1-9][0-9]* errors")
    let warnings = combinedOutput.matchCount(of: ", [1-9][0-9]* warnings")
    return Result(
      errors: terminationStatus == 0 ? 0 : (errors > 0 ? errors : 1),
      warnings: warnings)
  }

  static func scriptURL(for bundleRoot: URL) -> URL? {
    repoRootSearch(from: bundleRoot)?
      .appendingPathComponent("tools/localization/lint_locales.py")
  }

  private static func repoRootSearch(from start: URL) -> URL? {
    var url = start
    for _ in 0..<8 {
      if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
        return url
      }
      let parent = url.deletingLastPathComponent()
      if parent.path == url.path { break }
      url = parent
    }
    return nil
  }
}
