import Foundation

/// Describes a child process for `ProcessSupervisor` to launch.
public struct ProcessRequest: Sendable {
  public var executable: String
  public var arguments: [String]
  public var workingDirectory: URL?
  public var environment: [String: String]
  /// Routes stderr into the stdout pipe so terminals keep the original interleaving.
  public var mergesStandardError: Bool
  /// Bytes of each stream retained in `ProcessExit`. Output past the cap is still streamed.
  public var captureLimit: Int
  /// Time between SIGTERM and SIGKILL when the process tree is terminated.
  public var terminationGracePeriod: Duration
  /// How long to keep reading after the direct child exits, for descendants that
  /// inherited the pipes (for example `sleep 25 &`).
  public var drainPeriod: Duration

  public init(
    executable: String,
    arguments: [String] = [],
    workingDirectory: URL? = nil,
    environment: [String: String] = ProcessEnvironment.commandEnvironment(),
    mergesStandardError: Bool = true,
    captureLimit: Int = 0,
    terminationGracePeriod: Duration = .seconds(3),
    drainPeriod: Duration = .milliseconds(250)
  ) {
    self.executable = executable
    self.arguments = arguments
    self.workingDirectory = workingDirectory
    self.environment = environment
    self.mergesStandardError = mergesStandardError
    self.captureLimit = max(0, captureLimit)
    self.terminationGracePeriod = terminationGracePeriod
    self.drainPeriod = drainPeriod
  }
}

/// The environment every bundle command runs with: the app's environment plus the
/// common tool directories a Finder-launched app is missing from `PATH`.
public enum ProcessEnvironment {
  static let commonPaths = [
    "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
  ]

  public static func commandEnvironment(
    base: [String: String] = ProcessInfo.processInfo.environment,
    overrides: [String: String] = [:]
  ) -> [String: String] {
    var environment = base
    var pathParts = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
    for path in commonPaths where !pathParts.contains(path) {
      pathParts.append(path)
    }
    environment["PATH"] = pathParts.joined(separator: ":")
    return environment.merging(overrides) { _, override in override }
  }
}

extension Duration {
  var dispatchInterval: DispatchTimeInterval {
    let (seconds, attoseconds) = components
    return .nanoseconds(Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000))
  }
}
