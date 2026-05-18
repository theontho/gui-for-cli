import Foundation
import Testing

@testable import GUIForCLICLI

@Test func runGreetingUsesProvidedName() {
  #expect(Run.greeting(name: "Ada") == "Hello, Ada from gui-for-cli!")
}

@Test func localeLinterRunnerFindsToolsLocalizationScript() throws {
  let repoRoot = try Precheck.repoRoot(from: URL(fileURLWithPath: #filePath))
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

  #expect(
    try Precheck.repoRoot(from: start).standardizedFileURL.path == root.standardizedFileURL.path)
}

@Test func precheckRepoRootSearchStopsAtFilesystemRoot() throws {
  let fileManager = FileManager.default
  let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? fileManager.removeItem(at: root) }

  let start = root.appendingPathComponent("child")
  try fileManager.createDirectory(at: start, withIntermediateDirectories: true)

  #expect(throws: Error.self) {
    try Precheck.repoRoot(from: start)
  }
}
