import Foundation

public struct SetupCommandRunner: Sendable {
  public init() {}

  public func run(
    _ command: SetupCommand,
    onOutput: (@Sendable (String) -> Void)? = nil
  ) throws -> CommandRunResult {
    #if os(macOS)
      let outputPipe = Pipe()
      let outputAccumulator = CommandOutputAccumulator()
      let process = configuredProcess(for: command, output: outputPipe)
      streamOutput(from: outputPipe, into: outputAccumulator, onOutput: onOutput)
      try process.run()
      let exitStatus = waitForCompletion(
        process,
        outputPipe: outputPipe,
        outputAccumulator: outputAccumulator,
        onOutput: onOutput)

      return CommandRunResult(
        exitStatus: exitStatus,
        output: outputAccumulator.value()
      )
    #else
      throw SetupPlanError.unsupportedPlatform("this platform")
    #endif
  }
}

#if os(macOS)
  private func configuredProcess(for command: SetupCommand, output: Pipe) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command.executable)
    process.arguments = command.arguments
    process.currentDirectoryURL = command.workingDirectory
    process.standardOutput = output
    process.standardError = output
    process.environment = ProcessInfo.processInfo.environment.merging(command.environment) {
      _, new in new
    }
    return process
  }

  private func streamOutput(
    from outputPipe: Pipe,
    into accumulator: CommandOutputAccumulator,
    onOutput: (@Sendable (String) -> Void)?
  ) {
    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      accumulator.append(handle.availableData, onOutput: onOutput)
    }
  }

  private func waitForCompletion(
    _ process: Process,
    outputPipe: Pipe,
    outputAccumulator: CommandOutputAccumulator,
    onOutput: (@Sendable (String) -> Void)?
  ) -> Int32 {
    defer {
      outputPipe.fileHandleForReading.readabilityHandler = nil
    }
    process.waitUntilExit()
    outputPipe.fileHandleForReading.readabilityHandler = nil
    outputAccumulator.append(
      outputPipe.fileHandleForReading.readDataToEndOfFile(),
      onOutput: onOutput)
    return process.terminationStatus
  }
#endif

public struct CommandRunResult: Equatable, Sendable {
  public var exitStatus: Int32
  public var output: String
}

private final class CommandOutputAccumulator: @unchecked Sendable {
  private let lock = NSLock()
  private var output = ""

  func append(_ data: Data, onOutput: (@Sendable (String) -> Void)?) {
    guard !data.isEmpty else {
      return
    }
    let text = String(decoding: data, as: UTF8.self)
    guard !text.isEmpty else { return }

    lock.lock()
    output += text
    lock.unlock()
    onOutput?(text)
  }

  func value() -> String {
    lock.lock()
    let text = output
    lock.unlock()
    return text
  }
}
