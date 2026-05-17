import ArgumentParser
import Foundation
import GUIForCLICore

struct Precheck: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Check development environment readiness.")

  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    try options.validate()
    CLIOutput.line("Running precheck...", quiet: options.quiet)

    let checks = [
      checkCommand(label: "Swift toolchain", command: "swift", arguments: ["--version"]),
      checkCommand(label: "Xcode build tools", command: "xcodebuild", arguments: ["-version"]),
      checkCommand(label: "swift-format", command: "swift", arguments: ["format", "--version"]),
      checkRepositoryHooks(),
      checkConfigDirectory(),
    ]

    for check in checks {
      let prefix = check.passed ? "OK" : "FAIL"
      let detail = check.detail.isEmpty ? "" : " - \(check.detail)"
      CLIOutput.line("\(prefix) \(check.label)\(detail)", quiet: options.quiet && check.passed)
    }

    if checks.allSatisfy(\.passed) {
      CLIOutput.line("Precheck passed.", quiet: options.quiet)
    } else {
      throw ExitCode.failure
    }
  }
}

private struct CheckResult {
  let label: String
  let passed: Bool
  let detail: String
}

private func checkCommand(label: String, command: String, arguments: [String]) -> CheckResult {
  do {
    let result = try runCommand(command, arguments: arguments)
    if result.exitStatus == 0 {
      return CheckResult(label: label, passed: true, detail: firstLine(result.output))
    }

    return CheckResult(label: label, passed: false, detail: firstLine(result.output))
  } catch {
    return CheckResult(label: label, passed: false, detail: error.localizedDescription)
  }
}

private func checkConfigDirectory() -> CheckResult {
  let configDirectory = AppPaths.configDirectory()
  let fileManager = FileManager.default

  if fileManager.fileExists(atPath: configDirectory.path) {
    let probe = configDirectory.appendingPathComponent(".write-test-\(UUID().uuidString)")
    do {
      try Data().write(to: probe, options: [.atomic])
      try? fileManager.removeItem(at: probe)
      return CheckResult(label: "Config directory", passed: true, detail: configDirectory.path)
    } catch {
      return CheckResult(
        label: "Config directory", passed: false, detail: error.localizedDescription)
    }
  }

  let parent = nearestExistingParent(of: configDirectory)
  let writable = fileManager.isWritableFile(atPath: parent.path)
  return CheckResult(
    label: "Config directory parent",
    passed: writable,
    detail: parent.path
  )
}

private func checkRepositoryHooks() -> CheckResult {
  guard
    let repoRoot = findRepoRoot(
      from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
  else {
    return CheckResult(
      label: "Repository hooks",
      passed: false,
      detail: "not inside the repository; run from the repo root")
  }

  let script = repoRoot.appendingPathComponent("scripts/setup-hooks.py")
  guard FileManager.default.fileExists(atPath: script.path) else {
    return CheckResult(
      label: "Repository hooks",
      passed: false,
      detail: "scripts/setup-hooks.py was not found")
  }

  do {
    let result = try runCommand(
      "python3",
      arguments: ["scripts/setup-hooks.py", "--check"],
      currentDirectory: repoRoot)
    return CheckResult(
      label: "Repository hooks",
      passed: result.exitStatus == 0,
      detail: firstLine(result.output))
  } catch {
    return CheckResult(label: "Repository hooks", passed: false, detail: error.localizedDescription)
  }
}

private struct CommandResult {
  let exitStatus: Int32
  let output: String
}

private func runCommand(
  _ command: String,
  arguments: [String],
  currentDirectory: URL? = nil
) throws -> CommandResult {
  let process = Process()
  let output = Pipe()

  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = [command] + arguments
  process.currentDirectoryURL = currentDirectory
  process.standardOutput = output
  process.standardError = output

  try process.run()
  process.waitUntilExit()

  let data = output.fileHandleForReading.readDataToEndOfFile()
  let text = String(data: data, encoding: .utf8) ?? ""
  return CommandResult(exitStatus: process.terminationStatus, output: text)
}

func findRepoRoot(from start: URL) -> URL? {
  var candidatePath = start.standardizedFileURL.path
  let fileManager = FileManager.default
  while true {
    let candidate = URL(fileURLWithPath: candidatePath, isDirectory: true)
    let gitPath = candidate.appendingPathComponent(".git").path
    let hookScript = candidate.appendingPathComponent("scripts/setup-hooks.py").path
    if fileManager.fileExists(atPath: gitPath), fileManager.fileExists(atPath: hookScript) {
      return candidate
    }
    let parentPath = (candidatePath as NSString).deletingLastPathComponent
    if parentPath.isEmpty || parentPath == candidatePath { return nil }
    candidatePath = parentPath
  }
}

private func firstLine(_ value: String) -> String {
  value.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
}

private func nearestExistingParent(of url: URL) -> URL {
  var candidate = url.deletingLastPathComponent()
  let fileManager = FileManager.default

  while !fileManager.fileExists(atPath: candidate.path) {
    let next = candidate.deletingLastPathComponent()
    if next.path == candidate.path { return candidate }
    candidate = next
  }

  return candidate
}
