import Foundation

/// Runs bundle-test commands under the process supervisor, streaming output
/// and keeping a capped copy for the report.
public struct BundleTestProcessRunner: Sendable {
  private let maxOutputBytes: Int
  private let supervisor: ProcessSupervisor

  public init(maxOutputBytes: Int = 1_048_576, supervisor: ProcessSupervisor = .shared) {
    self.maxOutputBytes = max(0, maxOutputBytes)
    self.supervisor = supervisor
  }

  public func run(
    command: RenderedCommand,
    workingDirectory: URL?,
    environment: [String: String] = [:],
    timeoutSeconds: Double? = nil,
    onOutput: (@Sendable (String) -> Void)? = nil
  ) async throws -> BundleTestProcessResult {
    let resolved = PlatformProcessCommandResolver.resolve(command)
    return try await run(
      executable: resolved.executable,
      arguments: resolved.arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      timeoutSeconds: timeoutSeconds,
      onOutput: onOutput)
  }

  public func run(
    command: SetupCommand,
    timeoutSeconds: Double? = nil,
    onOutput: (@Sendable (String) -> Void)? = nil
  ) async throws -> BundleTestProcessResult {
    try await run(
      executable: command.executable,
      arguments: command.arguments,
      workingDirectory: command.workingDirectory,
      environment: command.environment,
      timeoutSeconds: timeoutSeconds,
      onOutput: onOutput)
  }

  private func run(
    executable: String,
    arguments: [String],
    workingDirectory: URL?,
    environment: [String: String],
    timeoutSeconds: Double?,
    onOutput: (@Sendable (String) -> Void)?
  ) async throws -> BundleTestProcessResult {
    let process = try supervisor.launch(
      ProcessRequest(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: ProcessEnvironment.commandEnvironment(overrides: environment),
        terminationGracePeriod: .seconds(2)))
    let maxOutputBytes = maxOutputBytes
    // Collected from the stream (not the exit capture) so a timed-out step
    // still reports the output it produced.
    async let collected: (text: String, truncated: Bool) = {
      var text = ""
      var truncated = false
      for await chunk in process.output {
        let piece = chunk.lines.map { "\($0)\n" }.joined()
        onOutput?(piece)
        let remaining = maxOutputBytes - text.utf8.count
        if piece.utf8.count <= remaining {
          text += piece
        } else {
          text += String(decoding: piece.utf8.prefix(max(remaining, 0)), as: UTF8.self)
          truncated = true
        }
      }
      return (text, truncated)
    }()
    let completion = await process.wait(timeout: timeoutSeconds.map { .seconds($0) })
    let output = await collected
    let text =
      output.truncated
      ? output.text + "[output truncated after \(maxOutputBytes) bytes]\n" : output.text
    switch completion {
    case .exited(let exit):
      return BundleTestProcessResult(termination: exit.termination, output: text)
    case .timedOut:
      return BundleTestProcessResult(termination: nil, output: text, timedOut: true)
    case .cancelled:
      throw CancellationError()
    }
  }
}

public struct BundleTestProcessResult: Equatable, Sendable {
  /// `nil` when the command timed out.
  public var termination: ProcessTermination?
  public var output: String
  public var timedOut: Bool

  public init(termination: ProcessTermination?, output: String, timedOut: Bool = false) {
    self.termination = termination
    self.output = output
    self.timedOut = timedOut
  }
}
