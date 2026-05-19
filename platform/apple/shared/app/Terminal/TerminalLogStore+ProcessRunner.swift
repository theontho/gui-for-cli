import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#endif

extension TerminalLogStore {
  #if os(macOS)
    private static let processOutputFlushIntervalNanoseconds: UInt64 = 200_000_000
  #endif

  func runCommand(tabID: UUID, command: RenderedCommand, workingDirectory: URL?) async {
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

  #if os(macOS)
    fileprivate func runProcess(
      tabID: UUID, command: RenderedCommand, workingDirectory: URL?
    ) async throws -> Int32 {
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let process = Process()
          let output = Pipe()
          let outputBuffer = TerminalOutputAccumulator()
          let processCommand = PlatformProcessCommandResolver.resolve(command)

          process.executableURL = URL(fileURLWithPath: processCommand.executable)
          process.arguments = processCommand.arguments
          process.currentDirectoryURL = workingDirectory
          process.standardOutput = output
          process.standardError = output
          process.environment = commandEnvironment()

          output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
              return
            }
            guard outputBuffer.append(text) else { return }
            Task.detached { [weak self] in
              try? await Task.sleep(nanoseconds: Self.processOutputFlushIntervalNanoseconds)
              await MainActor.run {
                self?.flushProcessOutput(to: tabID, flushingPartialLine: false)
              }
            }
          }

          process.terminationHandler = { [weak self] finishedProcess in
            let remaining = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: remaining, encoding: .utf8)
            let exitStatus = finishedProcess.terminationStatus
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
              if !remaining.isEmpty, let text {
                _ = outputBuffer.append(text)
              }
              self?.flushProcessOutput(to: tabID, flushingPartialLine: true)
              continuation.resume(returning: exitStatus)
            }
          }

          processes[tabID] = process
          outputBuffers[tabID] = outputBuffer
          do {
            try process.run()
          } catch {
            processes[tabID] = nil
            output.fileHandleForReading.readabilityHandler = nil
            outputBuffer.clear()
            outputBuffers[tabID] = nil
            continuation.resume(throwing: error)
          }
        }
      } onCancel: {
        Task { @MainActor in
          processes[tabID]?.terminate()
          processes[tabID] = nil
          outputBuffers[tabID]?.clear()
          outputBuffers[tabID] = nil
        }
      }
    }

    fileprivate func flushProcessOutput(to tabID: UUID, flushingPartialLine: Bool) {
      guard let buffer = outputBuffers[tabID] else { return }
      buffer.markScheduledFlushCompleted()
      let lines = buffer.drain(flushingPartialLine: flushingPartialLine)

      guard !lines.isEmpty else { return }
      append(lines.map { "[stdout] \($0)" }, to: tabID)
    }

    fileprivate func commandEnvironment() -> [String: String] {
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
