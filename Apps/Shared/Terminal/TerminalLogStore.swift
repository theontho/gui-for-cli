import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

@MainActor
final class TerminalLogStore: ObservableObject {
  @Published var tabs: [TerminalTab]
  @Published var selectedTabID: UUID?
  @Published private var runningCommandCounts: [String: Int] = [:]
  @Published private(set) var commandCompletionSerial = 0
  private(set) var lastCompletedCommand: String?

  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var exitCodeReference: [Int32: ExitCodeReferenceEntry]
  #if os(macOS)
    private var processes: [UUID: Process] = [:]
  #endif

  init(
    exitCodeReference: [ExitCodeReferenceEntry] = [],
    localizationLabels: BundleLocalizationLabels = BundleLocalizationLabels()
  ) {
    tabs = [
      TerminalTab(
        title: localizationLabels.terminalMainTabTitle, command: "main",
        lines: [
          "[08:00:00] GUI for CLI started.",
          "[08:00:00] Loaded sample bundle: WGS Extract.",
          "[08:00:00] Bundle setup can check PATH tools, bundled scripts, and Homebrew packages.",
        ])
    ]
    self.exitCodeReference = Dictionary(
      exitCodeReference.map { ($0.code, $0) },
      uniquingKeysWith: { first, _ in first })
    selectedTabID = tabs.first?.id
  }

  func updateExitCodeReference(_ entries: [ExitCodeReferenceEntry]) {
    exitCodeReference = Dictionary(
      entries.map { ($0.code, $0) },
      uniquingKeysWith: { first, _ in first })
  }

  func updateLocalizationLabels(_ labels: BundleLocalizationLabels) {
    guard !tabs.isEmpty else { return }
    tabs[0].title = labels.terminalMainTabTitle
  }

  var selectedTab: TerminalTab? {
    tabs.first { $0.id == selectedTabID }
  }

  var selectedLineCount: Int {
    selectedTab?.lines.count ?? 0
  }

  func isCommandRunning(_ command: String) -> Bool {
    runningCommandCounts[command, default: 0] > 0
  }

  func appendToMain(_ line: String) {
    guard let mainID = tabs.first?.id else { return }
    append(line, to: mainID)
  }

  func replaceMain(_ lines: [String]) {
    guard !tabs.isEmpty else { return }
    tabs[0].lines = lines
    selectedTabID = tabs[0].id
  }

  func start(title: String, command: RenderedCommand, workingDirectory: URL?) {
    let tab = TerminalTab(
      title: title, command: command.displayCommand,
      lines: [
        "$ \(command.displayCommand)",
        "[queued] Preparing command environment...",
      ],
      isRunning: true)
    tabs.append(tab)
    selectedTabID = tab.id
    incrementRunningCommand(command.displayCommand)

    tasks[tab.id] = Task { @MainActor [weak self] in
      await self?.runCommand(tabID: tab.id, command: command, workingDirectory: workingDirectory)
    }
  }

  func startSetup(_ commands: [SetupCommand]) {
    guard !commands.isEmpty else {
      appendToMain("[setup] Bundle has no setup steps.")
      return
    }

    let tab = TerminalTab(
      title: "Setup",
      command: "bundle setup",
      lines: commands.flatMap { command in
        [
          "==> \(command.label)",
          "$ \(command.displayCommand)",
        ]
      },
      isRunning: true
    )
    tabs.append(tab)
    selectedTabID = tab.id

    tasks[tab.id] = Task { @MainActor [weak self] in
      await self?.runSetup(tabID: tab.id, commands: commands)
    }
  }

  func closeTab(_ tabID: UUID) {
    guard tabs.first?.id != tabID else {
      return
    }

    tasks[tabID]?.cancel()
    tasks[tabID] = nil
    #if os(macOS)
      processes[tabID]?.terminate()
      processes[tabID] = nil
    #endif
    tabs.removeAll { $0.id == tabID }
    if selectedTabID == tabID {
      selectedTabID = tabs.first?.id
    }
  }

  private func runCommand(tabID: UUID, command: RenderedCommand, workingDirectory: URL?) async {
    defer {
      setTabRunning(false, tabID: tabID)
      decrementRunningCommand(command.displayCommand)
      publishCommandCompletion(command.displayCommand)
    }
    #if os(macOS)
      do {
        append("[running] \(command.displayCommand)", to: tabID)
        let exitStatus = try await runProcess(
          tabID: tabID,
          command: command,
          workingDirectory: workingDirectory)
        if Task.isCancelled {
          append("[cancelled] \(command.displayCommand)", to: tabID)
          setTabStatus(cancelledStatus(command: command.displayCommand), tabID: tabID)
        } else if exitStatus == 0 {
          append("[done] exit code 0", to: tabID)
        } else {
          append("[exit \(exitStatus)] \(command.displayCommand)", to: tabID)
          setTabStatus(
            exitFailureStatus(exitCode: exitStatus, command: command.displayCommand), tabID: tabID)
        }
      } catch is CancellationError {
        append("[cancelled] \(command.displayCommand)", to: tabID)
        setTabStatus(cancelledStatus(command: command.displayCommand), tabID: tabID)
      } catch {
        append("[error] \(error.localizedDescription)", to: tabID)
        setTabStatus(
          .processError(command: command.displayCommand, message: error.localizedDescription),
          tabID: tabID)
      }
      processes[tabID] = nil
      tasks[tabID] = nil
    #else
      append("[error] Command execution is only available on macOS.", to: tabID)
      tasks[tabID] = nil
    #endif
  }

  private func runSetup(tabID: UUID, commands: [SetupCommand]) async {
    defer {
      setTabRunning(false, tabID: tabID)
    }
    let runner = SetupCommandRunner()
    var warningStatus: TerminalTabStatus?
    for command in commands {
      if Task.isCancelled {
        append("[cancelled] setup stopped", to: tabID)
        setTabStatus(cancelledStatus(command: "bundle setup"), tabID: tabID)
        break
      }

      do {
        let result = try await Task.detached {
          try runner.run(command)
        }.value
        if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          append(result.output.trimmingCharacters(in: .newlines), to: tabID)
        }
        if result.exitStatus != 0 {
          append("[exit \(result.exitStatus)] \(command.label)", to: tabID)
          let status = exitFailureStatus(
            exitCode: result.exitStatus,
            command: command.label,
            severity: command.optional ? .warning : .error)
          if command.optional {
            warningStatus = warningStatus ?? status
          } else {
            setTabStatus(status, tabID: tabID)
            break
          }
        } else {
          append("[ok] \(command.label)", to: tabID)
        }
      } catch {
        append("[error] \(command.label): \(error.localizedDescription)", to: tabID)
        let status = TerminalTabStatus.processError(
          command: command.label,
          message: error.localizedDescription,
          severity: command.optional ? .warning : .error)
        if command.optional {
          warningStatus = warningStatus ?? status
        } else {
          setTabStatus(status, tabID: tabID)
          break
        }
      }
    }
    if let warningStatus, tabStatus(for: tabID) == nil {
      setTabStatus(warningStatus, tabID: tabID)
    }
    tasks[tabID] = nil
  }

  private func setTabRunning(_ isRunning: Bool, tabID: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    tabs[index].isRunning = isRunning
  }

  private func setTabStatus(_ status: TerminalTabStatus, tabID: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    tabs[index].status = status
  }

  private func tabStatus(for tabID: UUID) -> TerminalTabStatus? {
    tabs.first { $0.id == tabID }?.status
  }

  private func exitFailureStatus(
    exitCode: Int32,
    command: String,
    severity: TerminalTabStatusSeverity = .error
  ) -> TerminalTabStatus {
    TerminalTabStatus.exitFailure(
      exitCode: exitCode,
      command: command,
      severity: severity,
      reference: exitCodeReference[exitCode])
  }

  private func cancelledStatus(command: String) -> TerminalTabStatus {
    TerminalTabStatus.cancelled(command: command, reference: exitCodeReference[130])
  }

  private func incrementRunningCommand(_ command: String) {
    runningCommandCounts[command, default: 0] += 1
  }

  private func decrementRunningCommand(_ command: String) {
    let count = runningCommandCounts[command, default: 0]
    if count <= 1 {
      runningCommandCounts.removeValue(forKey: command)
    } else {
      runningCommandCounts[command] = count - 1
    }
  }

  private func publishCommandCompletion(_ command: String) {
    lastCompletedCommand = command
    commandCompletionSerial += 1
  }

  private func append(_ line: String, to tabID: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    tabs[index].lines.append(line)
  }

  #if os(macOS)
    private func runProcess(tabID: UUID, command: RenderedCommand, workingDirectory: URL?)
      async throws
      -> Int32
    {
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let process = Process()
          let output = Pipe()

          if command.executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
          } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command.executable] + command.arguments
          }
          process.currentDirectoryURL = workingDirectory
          process.standardOutput = output
          process.standardError = output
          process.environment = commandEnvironment()

          output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
              return
            }
            Task { @MainActor in
              self?.appendProcessOutput(text, to: tabID)
            }
          }

          process.terminationHandler = { [weak self] finishedProcess in
            let remaining = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: remaining, encoding: .utf8)
            let exitStatus = finishedProcess.terminationStatus
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
              if !remaining.isEmpty, let text {
                self?.appendProcessOutput(text, to: tabID)
              }
              continuation.resume(returning: exitStatus)
            }
          }

          processes[tabID] = process
          do {
            try process.run()
          } catch {
            processes[tabID] = nil
            output.fileHandleForReading.readabilityHandler = nil
            continuation.resume(throwing: error)
          }
        }
      } onCancel: {
        Task { @MainActor in
          processes[tabID]?.terminate()
          processes[tabID] = nil
        }
      }
    }

    private func appendProcessOutput(_ output: String, to tabID: UUID) {
      for line in output.split(whereSeparator: \.isNewline) {
        append("[stdout] \(line)", to: tabID)
      }
    }

    private func commandEnvironment() -> [String: String] {
      var environment = ProcessInfo.processInfo.environment
      let commonPaths = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
      ]
      var pathParts = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
      for path in commonPaths where !pathParts.contains(path) {
        pathParts.append(path)
      }
      environment["PATH"] = pathParts.joined(separator: ":")
      return environment
    }
  #endif
}
