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

  var tasks: [UUID: Task<Void, Never>] = [:]
  private var exitCodeReference: [Int32: ExitCodeReferenceEntry]
  private let logFileURL: URL?
  #if os(macOS)
    var processes: [UUID: Process] = [:]
    var outputBuffers: [UUID: TerminalOutputAccumulator] = [:]
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
          "[08:00:00] Run setup from the page header to check tools and prepare the bundle.",
        ])
    ]
    self.exitCodeReference = Dictionary(
      exitCodeReference.map { ($0.code, $0) },
      uniquingKeysWith: { first, _ in first })
    if let path = ProcessInfo.processInfo.environment["GUI_FOR_CLI_TERMINAL_LOG_FILE"],
      !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      logFileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    } else {
      logFileURL = nil
    }
    selectedTabID = tabs.first?.id
    appendToLogFile(tabs[0].text)
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
    selectedTab?.lineCount ?? 0
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
    tabs[0].replaceLines(lines)
    selectedTabID = tabs[0].id
    appendToLogFile(lines.joined(separator: "\n"))
  }

  func start(
    title: String,
    command: RenderedCommand,
    workingDirectory: URL?,
    inputSummary: String? = nil
  ) {
    let tab = TerminalTab(
      title: title, command: command.displayCommand,
      lines: [
        "$ \(command.displayCommand)",
        TerminalLogStore.actionExecutionLine(title: title, inputSummary: inputSummary),
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

  static func actionExecutionLine(title: String, inputSummary: String?) -> String {
    let inputs = inputSummary?.nonEmpty ?? "(none)"
    return "[action] Executing action \"\(title)\" with inputs \(inputs)"
  }

  func startSetup(
    _ commands: [SetupCommand],
    onStepStart: @escaping @MainActor (SetupCommand) -> Void = { _ in },
    onStepComplete: @escaping @MainActor (BundleSetupStepRunState) -> Void = { _ in },
    onComplete: @escaping @MainActor (BundleSetupRunState) -> Void = { _ in }
  ) {
    guard !commands.isEmpty else {
      appendToMain("[setup] Bundle has no setup steps.")
      return
    }

    let tab = TerminalTab(
      title: "Setup",
      command: "bundle setup",
      lines: ["Running setup..."],
      isRunning: true
    )
    tabs.append(tab)
    selectedTabID = tab.id

    tasks[tab.id] = Task { @MainActor [weak self] in
      await self?.runSetup(
        tabID: tab.id,
        commands: commands,
        onStepStart: onStepStart,
        onStepComplete: onStepComplete,
        onComplete: onComplete)
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
      outputBuffers[tabID]?.clear()
      outputBuffers[tabID] = nil
    #endif
    tabs.removeAll { $0.id == tabID }
    if selectedTabID == tabID {
      selectedTabID = tabs.first?.id
    }
  }

  func setTabRunning(_ isRunning: Bool, tabID: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    tabs[index].isRunning = isRunning
  }

  func setTabStatus(_ status: TerminalTabStatus, tabID: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    tabs[index].status = status
  }

  func tabStatus(for tabID: UUID) -> TerminalTabStatus? {
    tabs.first { $0.id == tabID }?.status
  }

  func exitFailureStatus(
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

  func cancelledStatus(command: String) -> TerminalTabStatus {
    TerminalTabStatus.cancelled(command: command, reference: exitCodeReference[130])
  }

  func incrementRunningCommand(_ command: String) {
    runningCommandCounts[command, default: 0] += 1
  }

  func decrementRunningCommand(_ command: String) {
    let count = runningCommandCounts[command, default: 0]
    if count <= 1 {
      runningCommandCounts.removeValue(forKey: command)
    } else {
      runningCommandCounts[command] = count - 1
    }
  }

  func publishCommandCompletion(_ command: String) {
    lastCompletedCommand = command
    commandCompletionSerial += 1
  }

  func append(_ line: String, to tabID: UUID) {
    append([line], to: tabID)
  }

  func append(_ lines: [String], to tabID: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    tabs[index].appendLines(lines)
    appendToLogFile(lines.joined(separator: "\n"))
  }

  private func appendToLogFile(_ text: String) {
    guard let logFileURL, !text.isEmpty else { return }
    do {
      try FileManager.default.createDirectory(
        at: logFileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      let entry = "[\(ISO8601DateFormatter().string(from: Date()))] \(text)\n"
      if FileManager.default.fileExists(atPath: logFileURL.path) {
        let handle = try FileHandle(forWritingTo: logFileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(entry.utf8))
      } else {
        try Data(entry.utf8).write(to: logFileURL, options: .atomic)
      }
    } catch {
      fputs("terminal log write failed: \(error.localizedDescription)\n", stderr)
    }
  }
}
