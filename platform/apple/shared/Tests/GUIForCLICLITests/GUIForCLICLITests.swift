import Foundation
import Testing

@testable import GUIForCLICLI

@Test func runGreetingUsesProvidedName() {
  #expect(Run.greeting(name: "Ada") == "Hello, Ada from gui-for-cli!")
}

@Test func localeLinterRunnerFindsToolsLocalizationScript() throws {
  let repoRoot = try #require(findRepoRoot(from: URL(fileURLWithPath: #filePath)))
  let bundleRoot = repoRoot.appendingPathComponent("examples/WGSExtract")

  let scriptURL = try #require(LocaleLinterRunner.scriptURL(for: bundleRoot))

  #expect(scriptURL.path.hasSuffix("tools/localization/lint_locales.py"))
  #expect(FileManager.default.fileExists(atPath: scriptURL.path))
}

@Test func localeLinterRunnerSkipsWhenRepoRootIsUnavailable() throws {
  let bundleRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(UUID().uuidString)
    .appendingPathComponent("bundle")

  let result = try LocaleLinterRunner.run(bundleRoot: bundleRoot, strict: true, quiet: true)

  #expect(result.errors == 0)
  #expect(result.warnings == 0)
}

@Test func localeLinterRunnerReportsParsedFailures() {
  let result = LocaleLinterRunner.result(
    from: "=== BadBundle\n  [fr] 12 keys, 2 errors, 1 warnings",
    terminationStatus: 1)

  #expect(result.errors > 0)
  #expect(result.warnings > 0)
}

@Test func precheckRepoRootSearchWalksPastTwelveParents() throws {
  let fileManager = FileManager.default
  let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? fileManager.removeItem(at: root) }

  try fileManager.createDirectory(
    at: root.appendingPathComponent(".git"),
    withIntermediateDirectories: true)
  let scripts = root.appendingPathComponent("scripts")
  try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
  try Data().write(to: scripts.appendingPathComponent("setup-hooks.py"))

  let start = (0..<14).reduce(root) { url, index in
    url.appendingPathComponent("level-\(index)")
  }
  try fileManager.createDirectory(at: start, withIntermediateDirectories: true)

  #expect(findRepoRoot(from: start)?.standardizedFileURL.path == root.standardizedFileURL.path)
}

@Test func precheckRepoRootSearchStopsAtFilesystemRoot() throws {
  let fileManager = FileManager.default
  let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? fileManager.removeItem(at: root) }

  let start = root.appendingPathComponent("child")
  try fileManager.createDirectory(at: start, withIntermediateDirectories: true)

  #expect(findRepoRoot(from: start) == nil)
}

@Test func precheckRepositoryHooksReportsMissingRepo() throws {
  let fileManager = FileManager.default
  let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? fileManager.removeItem(at: root) }
  try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

  let result = checkRepositoryHooks(currentDirectory: root)

  #expect(result.label == "Repository hooks")
  #expect(!result.passed)
  #expect(result.detail == "not inside the repository; run from the repo root")
}

@Test func precheckRepositoryHooksReportsMissingSetupScript() throws {
  let root = try temporaryRepoRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let result = checkRepositoryHooks(currentDirectory: root)

  #expect(result.label == "Repository hooks")
  #expect(!result.passed)
  #expect(result.detail == "scripts/setup-hooks.py was not found")
}

@Test func precheckRepositoryHooksRunsSetupCheckFromRepoRoot() throws {
  let root = try temporaryRepoRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let scripts = root.appendingPathComponent("scripts")
  try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
  try Data().write(to: scripts.appendingPathComponent("setup-hooks.py"))

  let nested = root.appendingPathComponent("a/b/c")
  try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

  var capturedCommand: String?
  var capturedArguments: [String]?
  var capturedDirectory: URL?
  let result = checkRepositoryHooks(currentDirectory: nested) { command, arguments, directory in
    capturedCommand = command
    capturedArguments = arguments
    capturedDirectory = directory
    return CommandResult(exitStatus: 0, output: "hooks ok\n")
  }

  #expect(result.label == "Repository hooks")
  #expect(result.passed)
  #expect(result.detail == "hooks ok")
  #expect(capturedCommand == "python3")
  #expect(capturedArguments == ["scripts/setup-hooks.py", "--check"])
  #expect(
    capturedDirectory?.resolvingSymlinksInPath().path
      == root.resolvingSymlinksInPath().path)
}

@Test func precheckRepositoryHooksReportsSetupCheckFailure() throws {
  let root = try temporaryRepoRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let scripts = root.appendingPathComponent("scripts")
  try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
  try Data().write(to: scripts.appendingPathComponent("setup-hooks.py"))

  let result = checkRepositoryHooks(currentDirectory: root) { _, _, _ in
    CommandResult(exitStatus: 1, output: "hooks stale\n")
  }

  #expect(result.label == "Repository hooks")
  #expect(!result.passed)
  #expect(result.detail == "hooks stale")
}

private func temporaryRepoRoot() throws -> URL {
  let fileManager = FileManager.default
  let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try fileManager.createDirectory(
    at: root.appendingPathComponent(".git"),
    withIntermediateDirectories: true)
  return root
}
