import ArgumentParser
import Foundation
import GUIForCLICore
import GUIForCLITestSupport
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

@Suite(.serialized)
struct CLIEnvironmentTests {
  @Test func cliExecutableCoversBundleConfigSetupAndRunFlows() throws {
    let fileManager = FileManager.default
    let repoRoot = try Precheck.repoRoot(from: URL(fileURLWithPath: #filePath))
    let configDirectory = fileManager.temporaryDirectory
      .appendingPathComponent("gui-for-cli-cli-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: configDirectory) }
    try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)

    let environment = [AppPaths.configDirectoryEnvironmentKey: configDirectory.path]

    try runCLI(["config", "init", "--quiet"], environment: environment)
    #expect(
      fileManager.fileExists(atPath: configDirectory.appendingPathComponent("config.json").path))

    try runCLI(["config", "show", "--quiet"], environment: environment)

    try runCLI(["run", "--quiet", "--name", "Ada"], environment: environment)

    let curlBundle = repoRoot.appendingPathComponent("examples/CurlWorkbench").path
    try runCLI(["bundle", "inspect", "--quiet", curlBundle])

    let wgsBundle = repoRoot.appendingPathComponent("examples/WGSExtract").path
    try runCLI(["bundle", "setup", "--quiet", "--dry-run", wgsBundle])
  }
}

private func runCLI(
  _ arguments: [String],
  environment: [String: String] = [:]
) throws {
  try withEnvironment(environment) {
    var command = try GUIForCLICLI.parseAsRoot(arguments)
    try command.run()
  }
}

private func withEnvironment(
  _ values: [String: String],
  run body: () throws -> Void
) throws {
  let previousValues = Dictionary(
    uniqueKeysWithValues: values.keys.map { key in
      (key, getenv(key).map { String(cString: $0) })
    })
  defer {
    for (key, previousValue) in previousValues {
      setEnvironmentVariable(key, previousValue)
    }
  }
  for (key, value) in values {
    setEnvironmentVariable(key, value)
  }
  try body()
}
