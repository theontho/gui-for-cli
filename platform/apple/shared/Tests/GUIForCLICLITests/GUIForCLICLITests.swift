import Foundation
import Testing

@testable import GUIForCLICLI

@Test func runGreetingUsesProvidedName() {
  #expect(Run.greeting(name: "Ada") == "Hello, Ada from gui-for-cli!")
}

@Test func localeLinterRunnerUsesToolsLocalizationScript() throws {
  let repoRoot = try #require(findRepoRoot(from: URL(fileURLWithPath: #filePath)))
  let bundleRoot = repoRoot.appendingPathComponent("examples/WGSExtract")

  let result = try LocaleLinterRunner.run(bundleRoot: bundleRoot, strict: true, quiet: true)

  #expect(result.errors == 0)
  #expect(result.warnings == 0)
}

private func findRepoRoot(from start: URL) -> URL? {
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
