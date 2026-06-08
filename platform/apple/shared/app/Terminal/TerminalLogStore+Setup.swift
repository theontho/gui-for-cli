import GUIForCLICore
import SwiftUI

extension TerminalLogStore {
  func runSetup(
    tabID: UUID,
    commands: [SetupCommand],
    onStepStart: @escaping @MainActor (SetupCommand) -> Void,
    onStepComplete: @escaping @MainActor (BundleSetupStepRunState) -> Void,
    onComplete: @escaping @MainActor (BundleSetupRunState) -> Void
  ) async {
    var results: [BundleSetupStepRunState] = []
    defer {
      setTabRunning(false, tabID: tabID)
    }
    let runner = SetupCommandRunner()
    var warningStatus: TerminalTabStatus?
    var wasCancelled = false
    for command in commands {
      if Task.isCancelled {
        wasCancelled = true
        append("[cancelled] setup stopped", to: tabID)
        setTabStatus(cancelledStatus(command: "bundle setup"), tabID: tabID)
        break
      }
      onStepStart(command)
      append("==> \(command.label)", to: tabID)
      append("$ \(command.displayCommand)", to: tabID)
      let stepStartedAt = Date()

      do {
        let (outputStream, outputContinuation) = AsyncStream.makeStream(of: String.self)
        let outputTask = Task { @MainActor in
          for await output in outputStream {
            append(output, to: tabID)
          }
        }
        let result: CommandRunResult
        do {
          result = try await Task.detached {
            try runner.run(command) { output in
              outputContinuation.yield(output)
            }
          }.value
        } catch {
          outputContinuation.finish()
          await outputTask.value
          throw error
        }
        outputContinuation.finish()
        await outputTask.value
        let status: String = result.exitStatus == 0 ? "ok" : command.optional ? "warning" : "failed"
        let durationMs = Self.setupDurationMs(since: stepStartedAt)
        let stepResult = BundleSetupStepRunState(
          id: command.id,
          label: command.label,
          kind: command.kind.rawValue,
          command: command.displayCommand,
          status: status,
          exitCode: result.exitStatus,
          durationMs: durationMs)
        results.append(stepResult)
        onStepComplete(stepResult)
        if result.exitStatus != 0 {
          append("[exit \(result.exitStatus)] \(command.label) (\(Self.setupDurationText(durationMs)))", to: tabID)
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
          append("[ok] \(command.label) (\(Self.setupDurationText(durationMs)))", to: tabID)
        }
      } catch {
        let stepStatus = command.optional ? "warning" : "failed"
        let durationMs = Self.setupDurationMs(since: stepStartedAt)
        let stepResult = BundleSetupStepRunState(
          id: command.id,
          label: command.label,
          kind: command.kind.rawValue,
          command: command.displayCommand,
          status: stepStatus,
          durationMs: durationMs)
        results.append(stepResult)
        onStepComplete(stepResult)
        append(
          "[error] \(command.label) (\(Self.setupDurationText(durationMs))): \(error.localizedDescription)",
          to: tabID)
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
    let summary = BundleSetupRunState(
      status: wasCancelled || results.contains { $0.status == "failed" } ? "failed" : "ok",
      results: results,
      completedAt: ISO8601DateFormatter().string(from: Date()))
    onComplete(summary)
    if let warningStatus, tabStatus(for: tabID) == nil {
      setTabStatus(warningStatus, tabID: tabID)
    }
    tasks[tabID] = nil
  }

  private static func setupDurationMs(since start: Date) -> Int {
    max(0, Int(Date().timeIntervalSince(start) * 1000))
  }

  private static func setupDurationText(_ durationMs: Int) -> String {
    if durationMs < 1000 {
      return String(format: "%.1fs", Double(durationMs) / 1000)
    }
    let totalSeconds = max(0, Int((Double(durationMs) / 1000).rounded()))
    if totalSeconds < 60 {
      return "\(totalSeconds)s"
    }
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    if minutes < 60 {
      return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
    }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
  }
}
