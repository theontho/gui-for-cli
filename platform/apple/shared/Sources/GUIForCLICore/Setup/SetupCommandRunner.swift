import Foundation

public struct SetupCommandRunner: Sendable {
  private let supervisor: ProcessSupervisor

  public init(supervisor: ProcessSupervisor = .shared) {
    self.supervisor = supervisor
  }

  /// Launches the setup step under the supervisor; stderr is merged into stdout.
  public func launch(_ command: SetupCommand) throws -> SupervisedProcess {
    #if os(macOS)
      try supervisor.launch(request(for: command))
    #else
      throw SetupPlanError.unsupportedPlatform("this platform")
    #endif
  }

  /// Runs the setup step to completion, streaming output lines as they arrive.
  /// Cancelling the calling task terminates the step's process tree.
  public func run(
    _ command: SetupCommand,
    onOutput: (@Sendable ([String]) -> Void)? = nil
  ) async throws -> CommandRunResult {
    let process = try launch(command)
    async let streamed: Void = {
      for await chunk in process.output {
        onOutput?(chunk.lines)
      }
    }()
    let completion = await process.wait()
    await streamed
    guard case .exited(let exit) = completion else {
      throw CancellationError()
    }
    return CommandRunResult(
      termination: exit.termination,
      output: String(decoding: exit.standardOutput, as: UTF8.self))
  }
}

#if os(macOS)
  private func request(for command: SetupCommand) -> ProcessRequest {
    let environment = ProcessEnvironment.commandEnvironment(overrides: command.environment)
    if command.requiresAdmin && usesNonInteractiveSudoAdminMode() {
      return ProcessRequest(
        executable: "/usr/bin/sudo",
        arguments: ["-n", "/usr/bin/env"]
          + environmentAssignmentArguments(elevatedCommandEnvironment(command))
          + [command.executable] + command.arguments,
        workingDirectory: command.workingDirectory,
        environment: environment,
        captureLimit: SetupCommandRunner.captureLimit)
    }
    if command.requiresAdmin {
      return ProcessRequest(
        executable: "/usr/bin/osascript",
        arguments: ["-e", elevatedAppleScript(for: command)],
        environment: environment,
        captureLimit: SetupCommandRunner.captureLimit)
    }
    return ProcessRequest(
      executable: command.executable,
      arguments: command.arguments,
      workingDirectory: command.workingDirectory,
      environment: environment,
      captureLimit: SetupCommandRunner.captureLimit)
  }

  private func usesNonInteractiveSudoAdminMode() -> Bool {
    ProcessInfo.processInfo.environment["GUI_FOR_CLI_MACOS_ADMIN_MODE"] == "sudo-noprompt"
  }

  func elevatedAppleScript(for command: SetupCommand) -> String {
    let shellScript = "\(elevatedShellScript(for: command)) 2>&1"
    return """
      do shell script \(appleScriptStringLiteral(shellScript)) with administrator privileges with prompt \(appleScriptStringLiteral(elevatedPrompt(for: command)))
      """
  }

  private func elevatedPrompt(for command: SetupCommand) -> String {
    let label = command.label.trimmingCharacters(in: .whitespacesAndNewlines)
    let setupStep = label.isEmpty ? "a setup step" : "the setup step \"\(label)\""
    return "GUI for CLI needs administrator privileges to run \(setupStep)."
  }

  private func elevatedShellScript(for command: SetupCommand) -> String {
    let assignmentArguments = environmentAssignmentArguments(elevatedCommandEnvironment(command))
    let commandArguments =
      ["/usr/bin/env"] + assignmentArguments + [command.executable] + command.arguments
    let invocation =
      commandArguments
      .map(ShellQuoting.quoted)
      .joined(separator: " ")
    return "cd \(ShellQuoting.quoted(command.workingDirectory.path)) && \(invocation)"
  }

  private func elevatedCommandEnvironment(_ command: SetupCommand) -> [String: String] {
    var environment = [
      "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    ]
    environment.merge(command.environment) { _, new in new }
    return environment
  }

  private func environmentAssignmentArguments(_ environment: [String: String]) -> [String] {
    environment.sorted { $0.key < $1.key }
      .filter { validEnvironmentName($0.key) }
      .map { "\($0.key)=\($0.value)" }
  }

  private func validEnvironmentName(_ value: String) -> Bool {
    value.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
  }

  private func appleScriptStringLiteral(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
  }

#endif

extension SetupCommandRunner {
  static let captureLimit = 1_048_576
}

public struct CommandRunResult: Equatable, Sendable {
  public var termination: ProcessTermination
  /// Merged stdout/stderr, capped at 1 MiB.
  public var output: String
}
