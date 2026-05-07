#!/usr/bin/env swift
import Darwin
import Foundation

private func run(_ command: String, _ arguments: [String]) -> (status: Int32, output: String) {
  let process = Process()
  let output = Pipe()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = [command] + arguments
  process.standardOutput = output
  process.standardError = output

  do {
    try process.run()
    process.waitUntilExit()
  } catch {
    return (1, error.localizedDescription)
  }

  let data = output.fileHandleForReading.readDataToEndOfFile()
  return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

private func gitConfig(_ key: String) -> String? {
  let result = run("git", ["config", key])
  guard result.status == 0 else { return nil }
  return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func parseDevID(_ path: String) -> [String: String] {
  guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
  var values: [String: String] = [:]

  for line in content.split(whereSeparator: \.isNewline) {
    let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
    if parts.count == 2 {
      values[parts[0].trimmingCharacters(in: .whitespaces)] =
        parts[1].trimmingCharacters(in: .whitespaces)
    }
  }

  return values
}

let devIDPath = ".dev_id"
guard FileManager.default.fileExists(atPath: devIDPath) else {
  fputs("Error: .dev_id file not found. Run 'swift scripts/dev-register.swift'.\n", stderr)
  exit(1)
}

let expected = parseDevID(devIDPath)
let currentName = gitConfig("user.name")
let currentEmail = gitConfig("user.email")
var errors: [String] = []

if currentName != expected["name"] {
  errors.append("Expected name '\(expected["name"] ?? "")', found '\(currentName ?? "")'")
}

if currentEmail != expected["email"] {
  errors.append("Expected email '\(expected["email"] ?? "")', found '\(currentEmail ?? "")'")
}

if !errors.isEmpty {
  fputs("Git identity mismatch.\n", stderr)
  for error in errors {
    fputs("  - \(error)\n", stderr)
  }
  fputs("Update your git config or rerun 'swift scripts/dev-register.swift'.\n", stderr)
  exit(1)
}

print("Git identity verified.")
