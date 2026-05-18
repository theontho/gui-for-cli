import ArgumentParser
import Foundation

struct Precheck: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Check development environment readiness.")

  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    try options.validate()
    let repoRoot = try Self.repoRoot()
    let scriptURL = repoRoot.appendingPathComponent("tools/precheck.py")
    guard FileManager.default.fileExists(atPath: scriptURL.path) else {
      throw ValidationError("tools/precheck.py was not found")
    }
    let result = try Self.runPythonTool(
      scriptURL,
      arguments: [options.quiet ? "--quiet" : nil, "--repo-root", repoRoot.path].compactMap { $0 },
      currentDirectory: repoRoot)
    if !result.output.isEmpty {
      CLIOutput.line(result.output.trimmingCharacters(in: .newlines), quiet: false)
    }
    if result.exitStatus != 0 {
      throw ExitCode(result.exitStatus)
    }
  }

  static func repoRoot(
    from start: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) throws -> URL {
    var candidatePath = start.standardizedFileURL.path
    let fileManager = FileManager.default
    while true {
      let candidate = URL(fileURLWithPath: candidatePath, isDirectory: true)
      if fileManager.fileExists(atPath: candidate.appendingPathComponent(".git").path) {
        return candidate
      }
      let parentPath = (candidatePath as NSString).deletingLastPathComponent
      if parentPath.isEmpty || parentPath == candidatePath {
        throw ValidationError("not inside the repository; run from the repo root")
      }
      candidatePath = parentPath
    }
  }

  static func runPythonTool(
    _ scriptURL: URL,
    arguments: [String],
    currentDirectory: URL
  ) throws -> CommandResult {
    let process = Process()
    let output = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", scriptURL.path] + arguments
    process.currentDirectoryURL = currentDirectory
    process.standardOutput = output
    process.standardError = output

    do {
      try process.run()
    } catch {
      throw ValidationError(
        """
        could not launch Python precheck via /usr/bin/env: \(error.localizedDescription). \
        Install Python 3 or adjust PATH.
        """)
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandResult(
      exitStatus: process.terminationStatus,
      output: String(decoding: data, as: UTF8.self))
  }
}

struct CommandResult {
  let exitStatus: Int32
  let output: String
}
