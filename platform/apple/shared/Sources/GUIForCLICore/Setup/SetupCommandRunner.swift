import Foundation

public struct SetupCommandRunner: Sendable {
  public init() {}

  public func run(_ command: SetupCommand) throws -> CommandRunResult {
    #if os(macOS)
      let process = Process()
      let output = Pipe()
      process.executableURL = URL(fileURLWithPath: command.executable)
      process.arguments = command.arguments
      process.currentDirectoryURL = command.workingDirectory
      process.standardOutput = output
      process.standardError = output
      process.environment = ProcessInfo.processInfo.environment.merging(command.environment) {
        _, new in
        new
      }

      try process.run()
      process.waitUntilExit()

      let data = output.fileHandleForReading.readDataToEndOfFile()
      return CommandRunResult(
        exitStatus: process.terminationStatus,
        output: String(data: data, encoding: .utf8) ?? ""
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
