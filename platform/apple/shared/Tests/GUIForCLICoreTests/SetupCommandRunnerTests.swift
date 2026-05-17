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

#if os(macOS)
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

  @Test func setupCommandRunnerStreamsOutputForFailingCommands() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let script = [
      "printf 'stdout before failure\\n'; ",
      "printf 'stderr before failure\\n' >&2; ",
      "exit 7",
    ].joined()

    let command = SetupCommand(
      id: "stream-failure",
      label: "Stream failure",
      kind: .setupScript,
      executable: "/bin/sh",
      arguments: ["-c", script],
      environment: [:],
      workingDirectory: root,
      optional: false)
    let chunks = StreamingOutputCollector()

    let result = try SetupCommandRunner().run(command) { chunk in
      chunks.append(chunk)
    }

    #expect(result.exitStatus == 7)
    #expect(result.output.contains("stdout before failure"))
    #expect(result.output.contains("stderr before failure"))
    #expect(chunks.joined().contains("stdout before failure"))
    #expect(chunks.joined().contains("stderr before failure"))
  }
#endif
