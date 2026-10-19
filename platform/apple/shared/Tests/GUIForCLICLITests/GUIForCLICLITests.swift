import ArgumentParser
import Foundation
import GUIForCLICore
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

#if os(macOS)
  /// Runs the built `gui-for-cli` executable with an explicit environment, so no
  /// test mutates this process's environment while others run in parallel.
  @Test func cliExecutableCoversBundleConfigSetupAndRunFlows() async throws {
    let fileManager = FileManager.default
    let repoRoot = try Precheck.repoRoot(from: URL(fileURLWithPath: #filePath))
    let configDirectory = fileManager.temporaryDirectory
      .appendingPathComponent("gui-for-cli-cli-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: configDirectory) }
    try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)

    let environment = [AppPaths.configDirectoryEnvironmentKey: configDirectory.path]

    try await runCLI(["config", "init", "--quiet"], environment: environment)
    #expect(
      fileManager.fileExists(atPath: configDirectory.appendingPathComponent("config.json").path))

    try await runCLI(["config", "show", "--quiet"], environment: environment)

    try await runCLI(["run", "--quiet", "--name", "Ada"], environment: environment)

    let curlBundle = repoRoot.appendingPathComponent("examples/CurlWorkbench").path
    try await runCLI(["bundle", "inspect", "--quiet", curlBundle])

    let wgsBundle = repoRoot.appendingPathComponent("examples/WGSExtract").path
    try await runCLI(["bundle", "setup", "--quiet", "--dry-run", wgsBundle])
  }

  private final class TestBundleLocator {}

  private func runCLI(
    _ arguments: [String],
    environment: [String: String] = [:]
  ) async throws {
    let productsDirectory = Bundle(for: TestBundleLocator.self).bundleURL
      .deletingLastPathComponent()
    let executable = productsDirectory.appendingPathComponent("gui-for-cli")
    let process = try ProcessSupervisor().launch(
      ProcessRequest(
        executable: executable.path,
        arguments: arguments,
        environment: ProcessEnvironment.commandEnvironment(overrides: environment),
        captureLimit: 65_536))
    guard case .exited(let exit) = await process.wait(timeout: .seconds(60)) else {
      Issue.record("gui-for-cli \(arguments.joined(separator: " ")) did not finish")
      return
    }
    #expect(
      exit.termination == .exited(0),
      "gui-for-cli \(arguments.joined(separator: " ")): \(String(decoding: exit.standardOutput, as: UTF8.self))"
    )
  }
#endif
