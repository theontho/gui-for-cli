import Foundation

public struct SetupCommandRunner: Sendable {
  public init() {}

  public func run(
    _ command: SetupCommand,
    onOutput: (@Sendable (String) -> Void)? = nil
  ) throws -> CommandRunResult {
    #if os(macOS)
      let process = Process()
      let output = Pipe()
      let outputAccumulator = CommandOutputAccumulator()
      process.executableURL = URL(fileURLWithPath: command.executable)
      process.arguments = command.arguments
      process.currentDirectoryURL = command.workingDirectory
      process.standardOutput = output
      process.standardError = output
      process.environment = ProcessInfo.processInfo.environment.merging(command.environment) {
        _, new in
        new
      }

      output.fileHandleForReading.readabilityHandler = { handle in
        outputAccumulator.append(handle.availableData, onOutput: onOutput)
      }
      defer {
        output.fileHandleForReading.readabilityHandler = nil
      }

      try process.run()
      process.waitUntilExit()
      output.fileHandleForReading.readabilityHandler = nil
      outputAccumulator.append(
        output.fileHandleForReading.readDataToEndOfFile(),
        onOutput: onOutput)

      return CommandRunResult(
        exitStatus: process.terminationStatus,
        output: outputAccumulator.value()
      )
    #else
      throw SetupPlanError.unsupportedPlatform("this platform")
    #endif
  }
}

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
