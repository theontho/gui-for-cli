import Foundation
import Testing

@testable import GUIForCLICore

private final class StreamingOutputCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var chunks: [String] = []

  func append(_ lines: [String]) {
    lock.withLock { chunks += lines }
  }

  func lines() -> [String] {
    lock.withLock { chunks }
  }
}

#if os(macOS)
  @Test func setupCommandRunnerStreamsOutputBeforeReturning() async throws {
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

    let result = try await SetupCommandRunner().run(command, onOutput: chunks.append)

    #expect(result.termination == .exited(0))
    #expect(result.output == "first\nsecond\n")
    #expect(chunks.lines() == ["first", "second"])
  }

  @Test func setupCommandRunnerStreamsOutputForFailingCommands() async throws {
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

    let result = try await SetupCommandRunner().run(command, onOutput: chunks.append)

    #expect(result.termination == .exited(7))
    #expect(result.output.contains("stdout before failure"))
    #expect(result.output.contains("stderr before failure"))
    #expect(chunks.lines() == ["stdout before failure", "stderr before failure"])
  }

  @Test func setupCommandRunnerCompletesDespiteBackgroundDescendants() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let command = SetupCommand(
      id: "daemon",
      label: "Daemon",
      kind: .setupScript,
      executable: "/bin/sh",
      arguments: ["-c", "echo ready; sleep 25 & exit 0"],
      environment: [:],
      workingDirectory: root,
      optional: false)
    let started = ContinuousClock.now

    let result = try await SetupCommandRunner().run(command)

    #expect(result.termination == .exited(0))
    #expect(ContinuousClock.now - started < .seconds(3))
  }

  @Test func cancellingSetupTerminatesTheStepProcessTree() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let command = SetupCommand(
      id: "long",
      label: "Long",
      kind: .setupScript,
      executable: "/bin/sh",
      arguments: ["-c", "trap 'exit 0' TERM; sleep 30"],
      environment: [:],
      workingDirectory: root,
      optional: false)
    let supervisor = ProcessSupervisor()
    let run = Task { try await SetupCommandRunner(supervisor: supervisor).run(command) }
    try await Task.sleep(for: .milliseconds(200))
    let processes = supervisor.activeProcesses
    #expect(processes.count == 1)

    run.cancel()
    await #expect(throws: CancellationError.self) { try await run.value }
    for _ in 0..<100 where processes.contains(where: \.isGroupAlive) {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(processes.allSatisfy { !$0.isGroupAlive })
  }

  @Test func elevatedSetupCommandIncludesAdminPrompt() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let command = SetupCommand(
      id: "xcode-tools",
      label: "Check Xcode Command Line Tools",
      kind: .setupScript,
      executable: "/bin/sh",
      arguments: ["scripts/check-xcode-command-line-tools.sh"],
      environment: [:],
      workingDirectory: root,
      optional: false,
      requiresAdmin: true)

    let script = elevatedAppleScript(for: command)
    let expectedPrompt =
      "GUI for CLI needs administrator privileges to run the setup step "
      + "\\\"Check Xcode Command Line Tools\\\"."

    #expect(script.contains("with administrator privileges with prompt"))
    #expect(script.contains(expectedPrompt))
    #expect(script.contains(" 2>&1"))
  }
#endif
