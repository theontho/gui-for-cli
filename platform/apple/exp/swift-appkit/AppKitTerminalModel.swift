import AppKit
import GUIForCLICore

struct AppKitTerminalTab: Identifiable {
  let id: UUID
  var title: String
  var command: String
  var lines: [String]
  var isRunning: Bool
  var status: AppKitTerminalStatus?

  init(
    id: UUID = UUID(),
    title: String,
    command: String,
    lines: [String],
    isRunning: Bool = false,
    status: AppKitTerminalStatus? = nil
  ) {
    self.id = id
    self.title = title
    self.command = command
    self.lines = lines
    self.isRunning = isRunning
    self.status = status
  }
}

struct AppKitTerminalStatus: Equatable {
  enum Severity {
    case success
    case warning
    case error
    case cancelled
  }

  var title: String
  var message: String
  var severity: Severity
}

@MainActor
final class AppKitTerminalModel {
  var tabs: [AppKitTerminalTab] = [] {
    didSet { onChange?() }
  }
  var selectedTabID: UUID? {
    didSet { onChange?() }
  }
  var onChange: (() -> Void)?
  var onCommandComplete: ((String) -> Void)?
  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var processes: [UUID: Process] = [:]
  private var outputRemainders: [UUID: String] = [:]
  private var runningCommandCounts: [String: Int] = [:]
  private let exitCodeReference: [Int32: ExitCodeReferenceEntry]

  init(labels: BundleLocalizationLabels, exitCodeReference: [ExitCodeReferenceEntry]) {
    tabs = [
      AppKitTerminalTab(
        title: labels.terminalMainTabTitle,
        command: "main",
        lines: [])
    ]
    selectedTabID = tabs.first?.id
    self.exitCodeReference = Dictionary(
      exitCodeReference.map { ($0.code, $0) },
      uniquingKeysWith: { first, _ in first })
  }

  var selectedTab: AppKitTerminalTab? {
    tabs.first { $0.id == selectedTabID }
  }

  func isCommandRunning(_ command: String) -> Bool {
    runningCommandCounts[command, default: 0] > 0
  }

  func appendToMain(_ line: String) {
    guard let id = tabs.first?.id else { return }
    append(line, to: id)
  }

  func start(title: String, command: RenderedCommand, workingDirectory: URL?) {
    let tab = AppKitTerminalTab(
      title: title,
      command: command.displayCommand,
      lines: ["$ \(command.displayCommand)", "[queued] Preparing command environment..."],
      isRunning: true)
    tabs.append(tab)
    selectedTabID = tab.id
    runningCommandCounts[command.displayCommand, default: 0] += 1

    tasks[tab.id] = Task { @MainActor [weak self] in
      await self?.runCommand(tabID: tab.id, command: command, workingDirectory: workingDirectory)
    }
  }

  func startSetup(
    _ commands: [SetupCommand],
    onComplete: @escaping @MainActor (BundleSetupRunState) -> Void
  ) {
    guard !commands.isEmpty else {
      appendToMain("[setup] Bundle has no setup steps.")
      return
    }

    let tab = AppKitTerminalTab(
      title: "Setup",
      command: "bundle setup",
      lines: ["Running setup..."],
      isRunning: true)
    tabs.append(tab)
    selectedTabID = tab.id

    tasks[tab.id] = Task { @MainActor [weak self] in
      await self?.runSetup(tabID: tab.id, commands: commands, onComplete: onComplete)
    }
  }

  func closeSelectedTab() {
    guard let selectedTabID, tabs.first?.id != selectedTabID else { return }
    tasks[selectedTabID]?.cancel()
    tasks[selectedTabID] = nil
    processes[selectedTabID]?.terminate()
    processes[selectedTabID] = nil
    outputRemainders[selectedTabID] = nil
    tabs.removeAll { $0.id == selectedTabID }
    self.selectedTabID = tabs.first?.id
  }

  private func runCommand(tabID: UUID, command: RenderedCommand, workingDirectory: URL?) async {
    defer {
      setTabRunning(false, tabID: tabID)
      decrementRunningCommand(command.displayCommand)
      processes[tabID] = nil
      tasks[tabID] = nil
      outputRemainders[tabID] = nil
      onCommandComplete?(command.displayCommand)
    }

    do {
      append("[running] \(command.displayCommand)", to: tabID)
      let exitStatus = try await runProcess(
        tabID: tabID,
        executable: command.executable,
        arguments: command.arguments,
        workingDirectory: workingDirectory,
        environment: [:])
      if Task.isCancelled {
        append("[cancelled] \(command.displayCommand)", to: tabID)
        setTabStatus(cancelledStatus(command: command.displayCommand), tabID: tabID)
      } else if exitStatus == 0 {
        append("[done] exit code 0", to: tabID)
        setTabStatus(
          AppKitTerminalStatus(
            title: "Done",
            message: "\(command.displayCommand) completed with exit code 0.",
            severity: .success),
          tabID: tabID)
      } else {
        append("[exit \(exitStatus)] \(command.displayCommand)", to: tabID)
        setTabStatus(
          exitFailureStatus(exitCode: exitStatus, command: command.displayCommand),
          tabID: tabID)
      }
    } catch is CancellationError {
      append("[cancelled] \(command.displayCommand)", to: tabID)
      setTabStatus(cancelledStatus(command: command.displayCommand), tabID: tabID)
    } catch {
      append("[error] \(error.localizedDescription)", to: tabID)
      setTabStatus(
        AppKitTerminalStatus(
          title: "Error",
          message: error.localizedDescription,
          severity: .error),
        tabID: tabID)
    }
  }

  private func runSetup(
    tabID: UUID,
    commands: [SetupCommand],
    onComplete: @escaping @MainActor (BundleSetupRunState) -> Void
  ) async {
    var results: [BundleSetupStepRunState] = []
    var failedError: String?

    for command in commands {
      if Task.isCancelled {
        failedError = "Setup cancelled."
        break
      }

      append("[setup] \(command.label)", to: tabID)
      append("$ \(command.displayCommand)", to: tabID)
      do {
        let exitStatus = try await runProcess(
          tabID: tabID,
          executable: command.executable,
          arguments: command.arguments,
          workingDirectory: command.workingDirectory,
          environment: command.environment)
        let status = exitStatus == 0 ? "passed" : (command.optional ? "optionalFailed" : "failed")
        results.append(
          BundleSetupStepRunState(
            id: command.id,
            label: command.label,
            kind: command.kind.rawValue,
            command: command.displayCommand,
            status: status,
            exitCode: exitStatus))
        if exitStatus != 0, !command.optional {
          failedError = "\(command.label) failed with exit code \(exitStatus)."
          break
        }
      } catch {
        results.append(
          BundleSetupStepRunState(
            id: command.id,
            label: command.label,
            kind: command.kind.rawValue,
            command: command.displayCommand,
            status: "failed"))
        failedError = error.localizedDescription
        break
      }
    }

    let setupRun = BundleSetupRunState(
      status: failedError == nil ? "passed" : "failed",
      results: results,
      completedAt: ISO8601DateFormatter().string(from: Date()),
      error: failedError)
    if let failedError {
      append("[setup:error] \(failedError)", to: tabID)
      setTabStatus(
        AppKitTerminalStatus(title: "Setup failed", message: failedError, severity: .error),
        tabID: tabID)
    } else {
      append("[setup] Complete.", to: tabID)
      setTabStatus(
        AppKitTerminalStatus(
          title: "Setup complete",
          message: "Bundle setup completed successfully.",
          severity: .success),
        tabID: tabID)
    }
    setTabRunning(false, tabID: tabID)
    tasks[tabID] = nil
    processes[tabID] = nil
    outputRemainders[tabID] = nil
    onComplete(setupRun)
    onCommandComplete?("bundle setup")
  }

  private func runProcess(
    tabID: UUID,
    executable: String,
    arguments: [String],
    workingDirectory: URL?,
    environment: [String: String]
  ) async throws -> Int32 {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        let output = Pipe()

        if executable.hasPrefix("/") {
          process.executableURL = URL(fileURLWithPath: executable)
          process.arguments = arguments
        } else {
          process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
          process.arguments = [executable] + arguments
        }
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = output
        process.standardError = output
        process.environment = commandEnvironment().merging(environment) { _, new in new }

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
          let data = handle.availableData
          guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
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
            self?.flushProcessOutputRemainder(for: tabID)
            continuation.resume(returning: exitStatus)
          }
        }

        processes[tabID] = process
        do {
          try process.run()
        } catch {
          processes[tabID] = nil
          outputRemainders[tabID] = nil
          output.fileHandleForReading.readabilityHandler = nil
          continuation.resume(throwing: error)
        }
      }
    } onCancel: {
      Task { @MainActor in
        self.processes[tabID]?.terminate()
        self.processes[tabID] = nil
      }
    }
  }

  private func appendProcessOutput(_ output: String, to tabID: UUID) {
    let combined = (outputRemainders[tabID] ?? "") + output
    let normalized =
      combined
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let segments = normalized.components(separatedBy: "\n")
    let completeSegments = normalized.hasSuffix("\n") ? segments.dropLast() : segments.dropLast()
    outputRemainders[tabID] = normalized.hasSuffix("\n") ? nil : segments.last

    for line in completeSegments {
      append("[stdout] \(line)", to: tabID)
    }
  }

  private func flushProcessOutputRemainder(for tabID: UUID) {
    if let remainder = outputRemainders[tabID], !remainder.isEmpty {
      append("[stdout] \(remainder)", to: tabID)
    }
    outputRemainders[tabID] = nil
  }

  private func setTabRunning(_ isRunning: Bool, tabID: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    tabs[index].isRunning = isRunning
  }

  private func setTabStatus(_ status: AppKitTerminalStatus, tabID: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    tabs[index].status = status
  }

  private func exitFailureStatus(exitCode: Int32, command: String) -> AppKitTerminalStatus {
    let reference = exitCodeReference[exitCode]
    let title = reference?.title ?? "Exit \(exitCode)"
    let summary = reference?.summary ?? "The command exited with status \(exitCode)."
    return AppKitTerminalStatus(
      title: title,
      message: "\(summary)\n\n\(command)",
      severity: reference?.severity == .warning ? .warning : .error)
  }

  private func cancelledStatus(command: String) -> AppKitTerminalStatus {
    let reference = exitCodeReference[130]
    return AppKitTerminalStatus(
      title: reference?.title ?? "Command cancelled",
      message: "\(reference?.summary ?? "The command was cancelled.")\n\n\(command)",
      severity: .cancelled)
  }

  private func decrementRunningCommand(_ command: String) {
    let count = runningCommandCounts[command, default: 0]
    if count <= 1 {
      runningCommandCounts.removeValue(forKey: command)
    } else {
      runningCommandCounts[command] = count - 1
    }
  }

  private func append(_ line: String, to tabID: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    tabs[index].lines.append(line)
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
}
