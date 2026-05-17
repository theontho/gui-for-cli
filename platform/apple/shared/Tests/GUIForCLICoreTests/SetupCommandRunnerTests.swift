import Foundation
import Testing

@testable import GUIForCLICore

private final class StreamingOutputCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var chunks: [String] = []

  func append(_ chunk: String) {
    lock.lock()
    chunks.append(chunk)
    lock.unlock()
  }

  func joined() -> String {
    lock.lock()
    let text = chunks.joined()
    lock.unlock()
    return text
  }
}

@Test func setupCommandRunnerStreamsOutputBeforeReturning() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }

  let command = SetupCommand(
    id: "stream",
    label: "Stream",
    kind: .setupScript,
    executable: "/bin/sh",
    arguments: ["-c", "printf first; printf '\\nsecond\\n'"],
    environment: [:],
    workingDirectory: root,
    optional: false)
  let chunks = StreamingOutputCollector()

  let result = try SetupCommandRunner().run(command) { chunk in
    chunks.append(chunk)
  }

  #expect(result.exitStatus == 0)
  #expect(result.output.contains("first"))
  #expect(result.output.contains("second"))
  #expect(chunks.joined().contains("first"))
  #expect(chunks.joined().contains("second"))
}
