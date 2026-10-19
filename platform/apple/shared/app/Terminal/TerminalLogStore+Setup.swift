import Foundation
import GUIForCLICore

extension TerminalLogStore {
  /// Opens the setup tab and runs the setup steps in order. Closing the tab, or
  /// `cancelSetup()`, cancels the run and terminates the current step's tree.
  func startSetup(
    _ commands: [SetupCommand],
    labels: BundleLocalizationLabels,
    onStepStart: @escaping @MainActor (SetupCommand) -> Void = { _ in },
    onStepComplete: @escaping @MainActor (BundleSetupStepRunState) -> Void = { _ in },
    onComplete: @escaping @MainActor (BundleSetupRunState) -> Void = { _ in }
  ) {
    guard !commands.isEmpty else {
      appendToMain("[setup] Bundle has no setup steps.")
      return
    }
    let tab = TerminalTab(
      kind: .setup,
      title: labels.setupTitle,
      command: "bundle setup",
      lines: [labels.setupRunningTitle],
      isRunning: true)
    addTab(tab)
    tasks[tab.id] = Task { [weak self] in
      guard let self else { return }
      let summary = await runSetup(
        commands, in: tab, onStepStart: onStepStart, onStepComplete: onStepComplete)
      tab.isRunning = false
      tasks[tab.id] = nil
      onComplete(summary)
    }
  }

  func cancelSetup() {
    for tab in tabs where tab.kind == .setup && tab.isRunning {
      cancel(tab.id)
    }
  }

  private func runSetup(
    _ commands: [SetupCommand],
    in tab: TerminalTab,
    onStepStart: @MainActor (SetupCommand) -> Void,
    onStepComplete: @MainActor (BundleSetupStepRunState) -> Void
  ) async -> BundleSetupRunState {
    let runner = SetupCommandRunner(supervisor: supervisor)
    var results: [BundleSetupStepRunState] = []
    var warningStatus: TerminalTabStatus?
    var failure: String?

    for command in commands {
      guard !Task.isCancelled else {
        failure = "cancelled"
        break
      }
      onStepStart(command)
      append(["==> \(command.label)", "$ \(command.displayCommand)"], to: tab)
      let startedAt = Date()
      let outcome: Result<ProcessTermination, any Error>
      do {
        guard case .exited(let exit) = try await run(runner.launch(command), in: tab) else {
          append(["[cancelled] \(command.label)"], to: tab)
          tab.status = cancelledStatus(command: "bundle setup")
          failure = "cancelled"
          break
        }
        outcome = .success(exit.termination)
      } catch {
        outcome = .failure(error)
      }

      let durationMs = SetupDurationFormatter.milliseconds(since: startedAt)
      let duration = SetupDurationFormatter.text(durationMs)
      let termination = try? outcome.get()
      let succeeded = termination?.isSuccess == true
      let stepResult = BundleSetupStepRunState(
        id: command.id,
        label: command.label,
        kind: command.kind.rawValue,
        command: command.displayCommand,
        status: succeeded ? "ok" : command.optional ? "warning" : "failed",
        exitCode: termination?.exitCode,
        signal: termination?.signal,
        durationMs: durationMs)
      results.append(stepResult)
      onStepComplete(stepResult)
      if succeeded {
        append(["[ok] \(command.label) (\(duration))"], to: tab)
        continue
      }

      let severity: TerminalTabStatusSeverity = command.optional ? .warning : .error
      let status: TerminalTabStatus
      switch outcome {
      case .success(let termination):
        append(["[\(termination.summary)] \(command.label) (\(duration))"], to: tab)
        status = failureStatus(termination, command: command.label, severity: severity)
        failure = "\(command.label) failed (\(termination.summary))"
      case .failure(let error):
        append(["[error] \(command.label) (\(duration)): \(error.localizedDescription)"], to: tab)
        status = processErrorStatus(
          command: command.label, message: error.localizedDescription, severity: severity)
        failure = "\(command.label): \(error.localizedDescription)"
      }
      if command.optional {
        warningStatus = warningStatus ?? status
        failure = nil
      } else {
        tab.status = status
        break
      }
    }

    if let warningStatus, tab.status == nil {
      tab.status = warningStatus
    }
    return BundleSetupRunState(
      status: failure == nil ? "ok" : "failed",
      results: results,
      completedAt: Date().formatted(.iso8601),
      error: failure)
  }
}
