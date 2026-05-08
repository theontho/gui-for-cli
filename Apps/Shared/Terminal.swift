import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct TerminalPane: View {
  @ObservedObject var store: TerminalLogStore
  let labels: BundleLocalizationLabels
  let textDirection: LayoutDirection

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "terminal")
          .font(.headline)
          .accessibilityLabel(labels.terminalCommandOutputLabel)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(store.tabs) { tab in
              TerminalTabButton(
                tab: tab,
                isSelected: store.selectedTabID == tab.id,
                close: { store.closeTab(tab.id) },
                select: { store.selectedTabID = tab.id }
              )
            }
          }
          .padding(.vertical, 2)
        }

        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

      Divider()

      ScrollViewReader { proxy in
        ScrollView {
          Text(store.selectedTab?.lines.joined(separator: "\n") ?? "")
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: terminalTextAlignment)
            .textSelection(.enabled)
            .padding(12)
            .environment(\.layoutDirection, textDirection)

          Color.clear
            .frame(height: 1)
            .id(Self.bottomAnchorID)
        }
        .onChange(of: store.selectedTabID) { _, _ in
          proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
        .onChange(of: store.selectedLineCount) { _, _ in
          proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
      }
      .background(.regularMaterial)
    }
  }

  private static let bottomAnchorID = "terminal-bottom"

  private var terminalTextAlignment: Alignment {
    textDirection == .rightToLeft ? .trailing : .leading
  }
}

struct TerminalTabButton: View {
  var tab: TerminalTab
  var isSelected: Bool
  var close: () -> Void
  var select: () -> Void
  @State private var showsStatusExplanation = false

  var body: some View {
    HStack(spacing: 4) {
      Button {
        select()
        if tab.status != nil {
          showsStatusExplanation = true
        }
      } label: {
        HStack(spacing: 4) {
          if tab.isRunning {
            ProgressView()
              .controlSize(.small)
          } else if let status = tab.status {
            Image(systemName: status.symbolName)
              .foregroundStyle(status.tint)
              .accessibilityLabel(status.accessibilityLabel)
          }
          Text(tab.title)
            .lineLimit(1)
        }
      }
      .buttonStyle(.plain)
      .popover(isPresented: $showsStatusExplanation, arrowEdge: .bottom) {
        if let status = tab.status {
          VStack(alignment: .leading, spacing: 8) {
            Label(status.title, systemImage: status.symbolName)
              .font(.headline)
              .foregroundStyle(status.tint)
            Text(status.blurb)
              .font(.callout)
              .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text(status.detail)
              .font(.system(.callout, design: .monospaced))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(14)
          .frame(width: 320, alignment: .leading)
        }
      }

      if !tab.isMain {
        Button(action: close) {
          Image(systemName: "xmark")
            .font(.caption2.weight(.semibold))
            .padding(3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.isRunning ? "Cancel \(tab.title)" : "Close \(tab.title)")
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(backgroundColor)
    .clipShape(Capsule())
    .overlay {
      Capsule()
        .strokeBorder(borderColor, lineWidth: tab.status == nil ? 0 : 1)
    }
  }

  private var backgroundColor: Color {
    if let status = tab.status {
      return status.tint.opacity(isSelected ? 0.28 : 0.16)
    }
    return isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)
  }

  private var borderColor: Color {
    tab.status?.tint.opacity(isSelected ? 0.65 : 0.35) ?? .clear
  }
}

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

struct TerminalTabStatus {
  var title: String
  var blurb: String
  var detail: String
  var symbolName: String
  var accessibilityLabel: String
  var severity: TerminalTabStatusSeverity

  var tint: Color {
    switch severity {
    case .warning:
      .orange
    case .error:
      .red
    case .cancelled:
      .yellow
    }
  }

  static func exitFailure(
    exitCode: Int32,
    command: String,
    severity: TerminalTabStatusSeverity,
    reference: ExitCodeReferenceEntry?
  ) -> TerminalTabStatus {
    let resolvedSeverity = reference?.severity.terminalSeverity ?? severity
    let title = reference?.title ?? "Exit code \(exitCode)"
    let summary =
      reference?.summary
      ?? "The command exited with a non-zero status. Check the command output for details."
    return TerminalTabStatus(
      title: title,
      blurb: summary,
      detail: "\(command) exited with code \(exitCode).",
      symbolName: resolvedSeverity == .warning
        ? "exclamationmark.triangle.fill" : "xmark.octagon.fill",
      accessibilityLabel: "Command exited with code \(exitCode)",
      severity: resolvedSeverity)
  }

  static func processError(
    command: String,
    message: String,
    severity: TerminalTabStatusSeverity = .error
  ) -> TerminalTabStatus {
    TerminalTabStatus(
      title: severity == .warning ? "Command warning" : "Command failed",
      blurb: "The command could not complete.",
      detail: "\(command)\n\(message)",
      symbolName: severity == .warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill",
      accessibilityLabel: severity == .warning ? "Command warning" : "Command failed",
      severity: severity)
  }

  static func cancelled(command: String, reference: ExitCodeReferenceEntry?) -> TerminalTabStatus {
    let summary =
      reference?.summary
      ?? "The command was cancelled before it finished. Partial output may have been produced."
    return TerminalTabStatus(
      title: reference?.title ?? "Command cancelled",
      blurb: summary,
      detail: "\(command) was cancelled.",
      symbolName: "minus.circle.fill",
      accessibilityLabel: "Command cancelled",
      severity: .cancelled)
  }
}

enum TerminalTabStatusSeverity {
  case warning
  case error
  case cancelled
}

extension ExitCodeSeverity {
  var terminalSeverity: TerminalTabStatusSeverity {
    switch self {
    case .warning:
      .warning
    case .error:
      .error
    }
  }
}

struct TerminalTab: Identifiable {
  let id = UUID()
  var title: String
  var command: String
  var lines: [String]
  var isRunning = false
  var status: TerminalTabStatus?

  var isMain: Bool {
    command == "main"
  }
}
