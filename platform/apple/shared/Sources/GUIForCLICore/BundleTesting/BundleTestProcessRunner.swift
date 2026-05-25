import Foundation
#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public struct BundleTestProcessRunner: Sendable {
  private let maxOutputBytes: Int

  public init(maxOutputBytes: Int = 1_048_576) {
    self.maxOutputBytes = max(0, maxOutputBytes)
  }

  public func run(
    command: RenderedCommand,
    workingDirectory: URL?,
    environment: [String: String] = [:],
    timeoutSeconds: Double? = nil,
    onOutput: (@Sendable (String) -> Void)? = nil
  ) throws -> BundleTestProcessResult {
    let resolved = PlatformProcessCommandResolver.resolve(command)
    return try run(
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
  ) throws -> BundleTestProcessResult {
    try run(
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
  ) throws -> BundleTestProcessResult {
    #if os(macOS) || os(Linux)
      let process = Process()
      let outputPipe = Pipe()
      let outputAccumulator = BundleTestOutputAccumulator(maxBytes: maxOutputBytes)

      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.currentDirectoryURL = workingDirectory
      process.standardOutput = outputPipe
      process.standardError = outputPipe
      process.environment = commandEnvironment(overrides: environment)

      try process.run()
      let outputGroup = DispatchGroup()
      outputGroup.enter()
      DispatchQueue.global(qos: .utility).async {
        while true {
          let data = outputPipe.fileHandleForReading.availableData
          guard !data.isEmpty else { break }
          outputAccumulator.append(data, onOutput: onOutput)
        }
        outputGroup.leave()
      }
      let timedOut = waitForCompletion(process, timeoutSeconds: timeoutSeconds)
      if timedOut {
        _ = outputGroup.wait(timeout: .now() + 2)
      } else {
        outputGroup.wait()
      }

      return BundleTestProcessResult(
        exitStatus: process.terminationStatus,
        output: outputAccumulator.value(),
        timedOut: timedOut)
    #else
      throw SetupPlanError.unsupportedPlatform("this platform")
    #endif
  }
}

public struct BundleTestProcessResult: Equatable, Sendable {
  public var exitStatus: Int32
  public var output: String
  public var timedOut: Bool

  public init(exitStatus: Int32, output: String, timedOut: Bool = false) {
    self.exitStatus = exitStatus
    self.output = output
    self.timedOut = timedOut
  }
}

#if os(macOS) || os(Linux)
  private func waitForCompletion(_ process: Process, timeoutSeconds: Double?) -> Bool {
    guard let timeoutSeconds, timeoutSeconds > 0 else {
      process.waitUntilExit()
      return false
    }

    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global(qos: .utility).async {
      process.waitUntilExit()
      group.leave()
    }
    guard group.wait(timeout: .now() + timeoutSeconds) == .timedOut else {
      return false
    }

    process.terminate()
    guard group.wait(timeout: .now() + 2) == .timedOut else {
      return true
    }

    forceKill(process)
    _ = group.wait(timeout: .now() + 2)
    return true
  }

  private func forceKill(_ process: Process) {
    guard process.isRunning else { return }
    #if canImport(Darwin)
      Darwin.kill(process.processIdentifier, SIGKILL)
    #elseif canImport(Glibc)
      Glibc.kill(process.processIdentifier, SIGKILL)
    #else
      process.terminate()
    #endif
  }

  private func commandEnvironment(overrides: [String: String]) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    let commonPaths = [
      "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]
    var pathParts = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
    for path in commonPaths where !pathParts.contains(path) {
      pathParts.append(path)
    }
    environment["PATH"] = pathParts.joined(separator: ":")
    return environment.merging(overrides) { _, override in override }
  }

  private final class BundleTestOutputAccumulator: @unchecked Sendable {
    private let maxBytes: Int
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false

    init(maxBytes: Int) {
      self.maxBytes = maxBytes
    }

    func append(_ data: Data, onOutput: (@Sendable (String) -> Void)?) {
      guard !data.isEmpty else { return }
      let text = String(decoding: data, as: UTF8.self)

      lock.lock()
      let remaining = maxBytes - self.data.count
      if remaining > 0 {
        self.data.append(contentsOf: data.prefix(remaining))
      }
      if data.count > max(remaining, 0) {
        truncated = true
      }
      lock.unlock()
      if !text.isEmpty {
        onOutput?(text)
      }
    }

    func value() -> String {
      lock.lock()
      let snapshot = data
      let wasTruncated = truncated
      lock.unlock()
      var text = String(decoding: snapshot, as: UTF8.self)
      if wasTruncated {
        text += "\n[output truncated after \(maxBytes) bytes]\n"
      }
      return text
    }
  }
#endif
