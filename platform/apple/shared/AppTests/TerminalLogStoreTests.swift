import Foundation
import GUIForCLICore
import Testing

@MainActor
@Suite struct TerminalLogStoreTests {
  let supervisor = ProcessSupervisor()

  private func makeStore(reference: [ExitCodeReferenceEntry] = []) -> TerminalLogStore {
    TerminalLogStore(
      exitCodeReference: reference,
      locale: Locale(identifier: "en"),
      supervisor: supervisor,
      logFileWriter: nil)
  }

  private func runToCompletion(_ script: String, in store: TerminalLogStore) async throws
    -> TerminalTab
  {
    store.start(title: "Test", command: shellCommand(script), workingDirectory: nil)
    let tab = try #require(store.tabs.last)
    #expect(try await eventually { !tab.isRunning })
    return tab
  }

  @Test func streamsOutputAndTracksRunningState() async throws {
    let store = makeStore()
    let command = shellCommand("printf 'héllo\\n日本\\n'")
    store.start(title: "Echo", command: command, workingDirectory: nil)
    #expect(store.isCommandRunning(command.displayCommand))
    let tab = try #require(store.tabs.last)

    #expect(try await eventually { !tab.isRunning })
    #expect(!store.isCommandRunning(command.displayCommand))
    #expect(store.commandCompletionSerial == 1)
    #expect(store.lastCompletedCommand == command.displayCommand)
    #expect(tab.output.lines.contains("[stdout] héllo"))
    #expect(tab.output.lines.contains("[stdout] 日本"))
    #expect(tab.output.lines.last == "[done] exit code 0")
    #expect(tab.status == nil)
    #expect(store.processes.isEmpty)
    #expect(store.tasks.isEmpty)
  }

  @Test func chattyOutputIsCappedAndKeepsTheMainActorResponsive() async throws {
    let store = makeStore()
    let lineCount = 300_000
    var worstDelay = Duration.zero
    let probe = Task { @MainActor in
      while !Task.isCancelled {
        let started = ContinuousClock.now
        try? await Task.sleep(for: .milliseconds(10))
        worstDelay = max(worstDelay, ContinuousClock.now - started - .milliseconds(10))
      }
    }
    defer { probe.cancel() }

    let tab = try await runToCompletion(
      "/usr/bin/yes 'chatty héllo 日本 ✓' | /usr/bin/head -n \(lineCount); echo end", in: store)

    #expect(tab.output.lines.count <= TerminalOutputBuffer.defaultLineLimit * 11 / 10)
    #expect(tab.output.lines.last == "[done] exit code 0")
    #expect(tab.output.lines.contains("[stdout] end"))
    #expect(tab.output.appendedLineCount >= lineCount)
    #expect(worstDelay < .milliseconds(250), "main actor stalled for \(worstDelay)")
  }

  @Test func exitFailuresUseTheBundleExitCodeReference() async throws {
    let store = makeStore(reference: [
      ExitCodeReferenceEntry(code: 3, title: "Missing input", summary: "Pick a file.")
    ])
    let tab = try await runToCompletion("exit 3", in: store)
    #expect(tab.status?.title == "Missing input")
    #expect(tab.output.lines.last?.hasPrefix("[exit 3]") == true)
  }

  @Test func signalDeathsAreReportedAsSignalsNotExitCodes() async throws {
    // A reference entry for 9 must not be used for a SIGKILL death.
    let store = makeStore(reference: [
      ExitCodeReferenceEntry(code: 9, title: "Exit nine", summary: "Wrong mapping.")
    ])
    let tab = try await runToCompletion("kill -KILL $$", in: store)
    #expect(tab.status?.title == "Terminated by SIGKILL")
    #expect(tab.output.lines.last?.hasPrefix("[signal 9 (SIGKILL)]") == true)
  }

  @Test func closingARunningTabKillsTheWholeProcessTree() async throws {
    let store = makeStore()
    store.start(
      title: "Wrapper",
      command: shellCommand("trap 'echo trapped' TERM; sleep 30; echo finished"),
      workingDirectory: nil)
    let tab = try #require(store.tabs.last)
    #expect(try await eventually { !supervisor.activeProcesses.isEmpty })
    let processes = supervisor.activeProcesses

    store.closeTab(tab.id)

    #expect(!store.tabs.contains { $0.id == tab.id })
    #expect(try await eventually { processes.allSatisfy { !$0.isGroupAlive } })
    #expect(try await eventually { supervisor.activeProcesses.isEmpty })
  }

  @Test func terminateAllStopsEveryCommand() async throws {
    let store = makeStore()
    for index in 0..<2 {
      store.start(title: "Sleep \(index)", command: shellCommand("sleep 30"), workingDirectory: nil)
    }
    #expect(try await eventually { supervisor.activeProcesses.count == 2 })
    let processes = supervisor.activeProcesses

    store.terminateAll()

    #expect(try await eventually { processes.allSatisfy { !$0.isGroupAlive } })
    #expect(try await eventually { store.tabs.dropFirst().allSatisfy { !$0.isRunning } })
    #expect(store.tabs.dropFirst().allSatisfy { $0.status?.severity == .cancelled })
  }

  @Test func cancellingSetupStopsTheCurrentStepAndReportsFailure() async throws {
    let store = makeStore()
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let step = SetupCommand(
      id: "long", label: "Long", kind: .setupScript, executable: "/bin/sh",
      arguments: ["-c", "sleep 30"], environment: [:], workingDirectory: root, optional: false)
    let next = SetupCommand(
      id: "next", label: "Next", kind: .setupScript, executable: "/bin/sh",
      arguments: ["-c", "true"], environment: [:], workingDirectory: root, optional: false)
    var summary: BundleSetupRunState?

    store.startSetup(
      [step, next], labels: BundleLocalizationLabels(), onComplete: { summary = $0 })
    #expect(try await eventually { !supervisor.activeProcesses.isEmpty })
    let processes = supervisor.activeProcesses
    store.cancelSetup()

    #expect(try await eventually { summary != nil })
    #expect(summary?.status == "failed")
    #expect(summary?.error == "cancelled")
    #expect(summary?.results.isEmpty == true)
    #expect(try await eventually { processes.allSatisfy { !$0.isGroupAlive } })
  }

  @Test func setupRecordsSignalDeathsPerStep() async throws {
    let store = makeStore()
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let step = SetupCommand(
      id: "crash", label: "Crash", kind: .setupScript, executable: "/bin/sh",
      arguments: ["-c", "kill -KILL $$"], environment: [:], workingDirectory: root,
      optional: false)
    var summary: BundleSetupRunState?

    store.startSetup([step], labels: BundleLocalizationLabels(), onComplete: { summary = $0 })

    #expect(try await eventually { summary != nil })
    let result = try #require(summary?.results.first)
    #expect(result.status == "failed")
    #expect(result.exitCode == nil)
    #expect(result.signal == SIGKILL)
  }
}
