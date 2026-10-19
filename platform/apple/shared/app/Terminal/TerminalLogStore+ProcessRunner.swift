import Foundation
import GUIForCLICore

extension TerminalLogStore {
  /// Opens a tab and runs an action's command in it.
  func start(
    title: String,
    command: RenderedCommand,
    workingDirectory: URL?,
    inputSummary: String? = nil
  ) {
    let tab = TerminalTab(
      kind: .action,
      title: title,
      command: command.displayCommand,
      lines: [
        "$ \(command.displayCommand)",
        Self.actionExecutionLine(title: title, inputSummary: inputSummary),
      ],
      isRunning: true)
    addTab(tab)
    incrementRunningCommand(command.displayCommand)
    tasks[tab.id] = Task { [weak self] in
      await self?.runCommand(command, in: tab, workingDirectory: workingDirectory)
    }
  }

  static func actionExecutionLine(title: String, inputSummary: String?) -> String {
    let inputs = inputSummary?.nonEmpty ?? "(none)"
    return "[action] Executing action \"\(title)\" with inputs \(inputs)"
  }

  private func runCommand(_ command: RenderedCommand, in tab: TerminalTab, workingDirectory: URL?)
    async
  {
    let displayCommand = command.displayCommand
    defer {
      tab.isRunning = false
      tasks[tab.id] = nil
      decrementRunningCommand(displayCommand)
      publishCommandCompletion(displayCommand)
    }
    append(["[running] \(displayCommand)"], to: tab)
    let resolved = PlatformProcessCommandResolver.resolve(command)
    let completion: ProcessCompletion
    do {
      completion = try await run(
        ProcessRequest(
          executable: resolved.executable,
          arguments: resolved.arguments,
          workingDirectory: workingDirectory),
        in: tab
      ) { "[stdout] \($0)" }
    } catch {
      append(["[error] \(error.localizedDescription)"], to: tab)
      tab.status = processErrorStatus(command: displayCommand, message: error.localizedDescription)
      return
    }

    switch completion {
    case .exited(let exit) where exit.termination.isSuccess:
      append(["[done] exit code 0"], to: tab)
    case .exited(let exit):
      append(["[\(exit.termination.summary)] \(displayCommand)"], to: tab)
      tab.status = failureStatus(exit.termination, command: displayCommand)
    case .cancelled, .timedOut:
      append(["[cancelled] \(displayCommand)"], to: tab)
      tab.status = cancelledStatus(command: displayCommand)
    }
  }

  /// Launches a supervised process for `tab`, streams its output into the tab,
  /// and waits for it. Cancelling the calling task terminates the process tree.
  func run(
    _ request: ProcessRequest,
    in tab: TerminalTab,
    format: @escaping (String) -> String = { $0 }
  ) async throws -> ProcessCompletion {
    try await run(supervisor.launch(request), in: tab, format: format)
  }

  func run(
    _ process: SupervisedProcess,
    in tab: TerminalTab,
    format: @escaping (String) -> String = { $0 }
  ) async -> ProcessCompletion {
    processes[tab.id] = process
    defer {
      if processes[tab.id] === process {
        processes[tab.id] = nil
      }
    }
    let reader = Task {
      for await chunk in process.output {
        append(chunk.lines.map(format), to: tab)
      }
    }
    let completion = await process.wait()
    guard case .exited(let exit) = completion else {
      reader.cancel()
      return completion
    }
    await reader.value
    if exit.droppedOutputLineCount > 0 {
      append(
        ["[output] \(exit.droppedOutputLineCount) lines were dropped while the view caught up."],
        to: tab)
    }
    return completion
  }
}
