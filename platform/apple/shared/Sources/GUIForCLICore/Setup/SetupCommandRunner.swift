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
    if command.requiresAdmin {
      let shellScript = elevatedShellScript(for: command)
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = [
        "-e",
        "do shell script \(appleScriptStringLiteral(shellScript)) with administrator privileges",
      ]
    } else {
      process.executableURL = URL(fileURLWithPath: command.executable)
      process.arguments = command.arguments
      process.currentDirectoryURL = command.workingDirectory
    }
    process.standardOutput = output
    process.standardError = output
    process.environment = ProcessInfo.processInfo.environment.merging(command.environment) {
      _, new in new
    }
    return process
  }

  private func elevatedShellScript(for command: SetupCommand) -> String {
    var environment = [
      "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    ]
    environment.merge(command.environment) { _, new in new }
    let assignmentArguments = environment.sorted { $0.key < $1.key }
      .filter { validEnvironmentName($0.key) }
      .map { "\($0.key)=\($0.value)" }
    let commandArguments =
      ["/usr/bin/env"] + assignmentArguments + [command.executable] + command.arguments
    let invocation =
      commandArguments
      .map(SetupCommand.shellQuoted)
      .joined(separator: " ")
    return "cd \(SetupCommand.shellQuoted(command.workingDirectory.path)) && \(invocation)"
  }

  private func validEnvironmentName(_ value: String) -> Bool {
    value.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
  }

  private func appleScriptStringLiteral(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
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
