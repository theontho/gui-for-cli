import Foundation
import GUIForCLICore
import Observation

/// Owns the terminal tabs and the processes they run. Views observe only what
/// they read: the tab strip reads `tabs`, action buttons read running state,
/// and each tab's output buffer is observed by the terminal text view alone.
@MainActor
@Observable
final class TerminalLogStore {
  private(set) var tabs: [TerminalTab]
  var selectedTabID: UUID?
  private var runningCommandCounts: [String: Int] = [:]
  private(set) var commandCompletionSerial = 0
  @ObservationIgnored private(set) var lastCompletedCommand: String?

  /// Labels and language for app chrome text produced here (tab statuses).
  @ObservationIgnored private var labels: BundleLocalizationLabels
  @ObservationIgnored private var locale: Locale
  @ObservationIgnored let supervisor: ProcessSupervisor
  @ObservationIgnored var tasks: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored var processes: [UUID: SupervisedProcess] = [:]
  @ObservationIgnored private var exitCodeReference: [Int32: ExitCodeReferenceEntry] = [:]
  @ObservationIgnored private let logFileWriter: TerminalLogFileWriter?

  init(
    exitCodeReference: [ExitCodeReferenceEntry] = [],
    localizationLabels: BundleLocalizationLabels = BundleLocalizationLabels(),
    locale: Locale = .current,
    startupLines: [String] = [],
    supervisor: ProcessSupervisor = .shared,
    logFileWriter: TerminalLogFileWriter? = .fromEnvironment()
  ) {
    let main = TerminalTab(
      kind: .main, title: localizationLabels.terminalMainTabTitle, command: "main",
      lines: startupLines)
    tabs = [main]
    selectedTabID = main.id
    labels = localizationLabels
    self.locale = locale
    self.supervisor = supervisor
    self.logFileWriter = logFileWriter
    updateExitCodeReference(exitCodeReference)
    appendToLogFile(startupLines)
  }

  func updateExitCodeReference(_ entries: [ExitCodeReferenceEntry]) {
    exitCodeReference = Dictionary(
      entries.map { ($0.code, $0) },
      uniquingKeysWith: { first, _ in first })
  }

  func updateLocalization(_ labels: BundleLocalizationLabels, locale: Locale) {
    self.labels = labels
    self.locale = locale
    tabs.first?.title = labels.terminalMainTabTitle
  }

  var selectedTab: TerminalTab? {
    tabs.first { $0.id == selectedTabID }
  }

  func isCommandRunning(_ command: String) -> Bool {
    runningCommandCounts[command, default: 0] > 0
  }

  func appendToMain(_ line: String) {
    guard let main = tabs.first else { return }
    append([line], to: main)
  }

  func append(_ lines: [String], to tab: TerminalTab) {
    tab.output.append(lines)
    appendToLogFile(lines)
  }

  // MARK: - Tabs

  func addTab(_ tab: TerminalTab) {
    tabs.append(tab)
    selectedTabID = tab.id
  }

  /// Closes a tab; a running command or setup is cancelled and its process tree terminated.
  func closeTab(_ tabID: UUID) {
    guard let tab = tabs.first(where: { $0.id == tabID }), !tab.isMain else { return }
    cancel(tabID)
    tabs.removeAll { $0.id == tabID }
    if selectedTabID == tabID {
      selectedTabID = tabs.first?.id
    }
  }

  /// Terminates every process this store started (bundle teardown, window close).
  func terminateAll() {
    for tabID in Array(tasks.keys) {
      cancel(tabID)
    }
  }

  func cancel(_ tabID: UUID) {
    tasks.removeValue(forKey: tabID)?.cancel()
    processes.removeValue(forKey: tabID)?.terminate()
  }

  // MARK: - Running state

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

  // MARK: - Statuses

  func failureStatus(
    _ termination: ProcessTermination,
    command: String,
    severity: TerminalTabStatusSeverity = .error
  ) -> TerminalTabStatus {
    switch termination {
    case .exited(let code):
      TerminalTabStatus.exitFailure(
        exitCode: code, command: command, severity: severity,
        reference: exitCodeReference[code], labels: labels, locale: locale)
    case .signaled(let signal):
      TerminalTabStatus.signaled(
        signal: signal, command: command, severity: severity, locale: locale)
    }
  }

  func cancelledStatus(command: String) -> TerminalTabStatus {
    TerminalTabStatus.cancelled(
      command: command, reference: exitCodeReference[130], locale: locale)
  }

  func processErrorStatus(
    command: String, message: String, severity: TerminalTabStatusSeverity = .error
  ) -> TerminalTabStatus {
    TerminalTabStatus.processError(
      command: command, message: message, severity: severity, labels: labels, locale: locale)
  }

  private func appendToLogFile(_ lines: [String]) {
    guard let logFileWriter, !lines.isEmpty else { return }
    logFileWriter.append(lines.joined(separator: "\n"))
  }
}
