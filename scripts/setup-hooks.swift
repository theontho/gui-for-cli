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

let rootResult = run("git", ["rev-parse", "--show-toplevel"])
guard rootResult.status == 0 else {
  print("Skipping hook install: not inside a Git repository.")
  exit(0)
}

let root = rootResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
let hooksDirectory = URL(fileURLWithPath: root)
  .appendingPathComponent(".git", isDirectory: true)
  .appendingPathComponent("hooks", isDirectory: true)
try FileManager.default.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)

let hooks: [(name: String, body: String)] = [
  (
    "pre-commit",
    """
    #!/bin/sh
    set -eu
    cd "$(git rev-parse --show-toplevel)"
    swift scripts/verify-dev.swift
    make lint
    """
  ),
  (
    "pre-push",
    """
    #!/bin/sh
    set -eu
    cd "$(git rev-parse --show-toplevel)"
    swift scripts/verify-dev.swift
    make test
    make build-cli
    """
  ),
]

for hook in hooks {
  let path = hooksDirectory.appendingPathComponent(hook.name, isDirectory: false)
  try "\(hook.body)\n".write(to: path, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
}

print("Installed pre-commit and pre-push hooks.")
