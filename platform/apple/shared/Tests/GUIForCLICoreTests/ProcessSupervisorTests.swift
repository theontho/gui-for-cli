import Foundation
import Testing

@testable import GUIForCLICore

#if os(macOS)
  @Suite struct ProcessSupervisorTests {
    let supervisor = ProcessSupervisor()

    private func shell(
      _ script: String,
      mergesStandardError: Bool = true,
      captureLimit: Int = 1_048_576,
      grace: Duration = .milliseconds(500)
    ) throws -> SupervisedProcess {
      try supervisor.launch(
        ProcessRequest(
          executable: "/bin/sh",
          arguments: ["-c", script],
          mergesStandardError: mergesStandardError,
          captureLimit: captureLimit,
          terminationGracePeriod: grace))
    }

    private func exit(of process: SupervisedProcess) async throws -> ProcessExit {
      guard case .exited(let exit) = await process.wait() else {
        Issue.record("process did not exit normally")
        throw CancellationError()
      }
      return exit
    }

    private func waitUntilGroupIsGone(_ process: SupervisedProcess) async throws -> Bool {
      for _ in 0..<100 where process.isGroupAlive {
        try await Task.sleep(for: .milliseconds(50))
      }
      return !process.isGroupAlive
    }

    @Test func streamsLinesAndCapturesSeparateStreams() async throws {
      let process = try shell(
        "printf 'out 1\\nout 2\\n'; printf 'err\\n' >&2; exit 3", mergesStandardError: false)
      async let lines = process.output.reduce(into: [ProcessOutputChunk]()) { $0.append($1) }
      let exit = try await exit(of: process)

      #expect(exit.termination == .exited(3))
      #expect(String(decoding: exit.standardOutput, as: UTF8.self) == "out 1\nout 2\n")
      #expect(String(decoding: exit.standardError, as: UTF8.self) == "err\n")
      let chunks = await lines
      #expect(
        chunks.filter { $0.stream == .standardOutput }.flatMap(\.lines) == ["out 1", "out 2"])
      #expect(chunks.filter { $0.stream == .standardError }.flatMap(\.lines) == ["err"])
    }

    @Test func decodesMultibyteOutputAcrossPipeReads() async throws {
      let process = try shell("/usr/bin/yes 'é日' | /usr/bin/head -n 40000")
      async let lines = process.output.reduce(into: [String]()) { $0 += $1.lines }
      _ = try await exit(of: process)
      let received = await lines
      #expect(received.count == 40000)
      #expect(received.allSatisfy { $0 == "é日" })
    }

    @Test func completesWhenABackgroundDescendantKeepsThePipeOpen() async throws {
      let started = ContinuousClock.now
      let process = try shell("printf '{\"ok\":true}\\n'; sleep 25 & exit 0")
      defer { process.signalGroup(SIGKILL) }
      let exit = try await exit(of: process)

      #expect(ContinuousClock.now - started < .seconds(3))
      #expect(exit.termination == .exited(0))
      #expect(String(decoding: exit.standardOutput, as: UTF8.self) == "{\"ok\":true}\n")
    }

    @Test func reportsSignalDeathsAsSignals() async throws {
      let process = try shell("kill -KILL $$")
      let exit = try await exit(of: process)
      #expect(exit.termination == .signaled(SIGKILL))
      #expect(exit.termination.exitCode == nil)
      #expect(exit.termination.summary == "signal 9 (SIGKILL)")
    }

    @Test func terminateKillsTheTreeEvenWhenTheWrapperTrapsTerm() async throws {
      // A wrapper that traps TERM and runs a foreground child defers the signal
      // until the child finishes; only signalling the group stops the child.
      let process = try shell("trap 'echo trapped; exit 0' TERM; sleep 30; echo finished")
      try await Task.sleep(for: .milliseconds(200))
      process.terminate()
      let exit = try await exit(of: process)

      let output = String(decoding: exit.standardOutput, as: UTF8.self)
      #expect(output.contains("trapped"))
      #expect(!output.contains("finished"))
      #expect(try await waitUntilGroupIsGone(process))
    }

    @Test func terminateEscalatesToSigkillWhenTermIsIgnored() async throws {
      let started = ContinuousClock.now
      let process = try shell("trap '' TERM; sleep 30", grace: .milliseconds(300))
      try await Task.sleep(for: .milliseconds(200))
      process.terminate()
      let exit = try await exit(of: process)

      #expect(exit.termination == .signaled(SIGKILL))
      #expect(ContinuousClock.now - started < .seconds(3))
      #expect(try await waitUntilGroupIsGone(process))
    }

    @Test func timeoutReturnsOnScheduleAndKillsTheTree() async throws {
      let started = ContinuousClock.now
      let process = try shell("trap '' TERM; sleep 30", grace: .milliseconds(300))
      let completion = await process.wait(timeout: .milliseconds(300))

      #expect(completion == .timedOut)
      #expect(ContinuousClock.now - started < .seconds(1))
      #expect(try await waitUntilGroupIsGone(process))
      #expect(try await waitUntilSettled(process))
    }

    @Test func cancellingTheWaitingTaskTerminatesTheTree() async throws {
      let process = try shell("sleep 30 & sleep 30")
      let waiter = Task { await process.wait() }
      try await Task.sleep(for: .milliseconds(200))
      waiter.cancel()

      #expect(await waiter.value == .cancelled)
      #expect(try await waitUntilGroupIsGone(process))
    }

    @Test func terminateAllBlocksUntilEveryTreeIsGone() throws {
      let processes = try (0..<3).map { _ in try shell("trap '' TERM; sleep 30") }
      supervisor.terminateAll(waitingUpTo: .seconds(1))
      #expect(processes.allSatisfy { !$0.isGroupAlive })
    }

    @Test func launchFailureThrowsAndIsNotTracked() {
      #expect(throws: ProcessSupervisorError.self) {
        try supervisor.launch(ProcessRequest(executable: "/nonexistent/tool"))
      }
      #expect(supervisor.activeProcesses.isEmpty)
    }

    private func waitUntilSettled(_ process: SupervisedProcess) async throws -> Bool {
      for _ in 0..<100 where supervisor.activeProcesses.contains(where: { $0 === process }) {
        try await Task.sleep(for: .milliseconds(50))
      }
      return !supervisor.activeProcesses.contains { $0 === process }
    }
  }
#endif
