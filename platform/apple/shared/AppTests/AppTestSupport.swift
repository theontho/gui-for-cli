import Foundation
import GUIForCLICore

/// Polls `condition` on the main actor until it holds or `timeout` elapses.
@MainActor
func eventually(
  timeout: Duration = .seconds(5),
  _ condition: () -> Bool
) async throws -> Bool {
  let deadline = ContinuousClock.now + timeout
  while !condition() {
    guard ContinuousClock.now < deadline else { return false }
    try await Task.sleep(for: .milliseconds(20))
  }
  return true
}

func makeTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("gui-for-cli-app-tests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

func shellCommand(_ script: String) -> RenderedCommand {
  RenderedCommand(executable: "/bin/sh", arguments: ["-c", script])
}
