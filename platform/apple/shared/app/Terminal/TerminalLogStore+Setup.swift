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
        let stepResult = BundleSetupStepRunState(
          id: command.id,
          label: command.label,
          kind: command.kind.rawValue,
          command: command.displayCommand,
          status: status,
          exitCode: result.exitStatus)
        results.append(stepResult)
        onStepComplete(stepResult)
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
        let stepStatus = command.optional ? "warning" : "failed"
        let stepResult = BundleSetupStepRunState(
          id: command.id,
          label: command.label,
          kind: command.kind.rawValue,
          command: command.displayCommand,
          status: stepStatus)
        results.append(stepResult)
        onStepComplete(stepResult)
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
}
