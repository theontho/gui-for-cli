import GUIForCLICore
import SwiftUI

extension TerminalLogStore {
  func runSetup(tabID: UUID, commands: [SetupCommand]) async {
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
}
