import Foundation

/// How a child process ended: a normal exit with a status, or death by a signal.
public enum ProcessTermination: Equatable, Sendable {
  case exited(Int32)
  case signaled(Int32)

  public var isSuccess: Bool { self == .exited(0) }

  public var exitCode: Int32? {
    if case .exited(let code) = self { return code }
    return nil
  }

  public var signal: Int32? {
    if case .signaled(let signal) = self { return signal }
    return nil
  }

  /// Shell-style status (`128 + signal` for signal deaths), for CLI exit codes only.
  public var shellStatus: Int32 {
    switch self {
    case .exited(let code): code
    case .signaled(let signal): 128 + signal
    }
  }

  /// "exit 3" or "signal 9 (SIGKILL)".
  public var summary: String {
    switch self {
    case .exited(let code): "exit \(code)"
    case .signaled(let signal): "signal \(signal) (\(Self.signalName(signal)))"
    }
  }

  public static func signalName(_ signal: Int32) -> String {
    signalNames[signal] ?? "SIG\(signal)"
  }

  private static let signalNames: [Int32: String] = [
    SIGHUP: "SIGHUP", SIGINT: "SIGINT", SIGQUIT: "SIGQUIT", SIGILL: "SIGILL",
    SIGTRAP: "SIGTRAP", SIGABRT: "SIGABRT", SIGFPE: "SIGFPE", SIGKILL: "SIGKILL",
    SIGBUS: "SIGBUS", SIGSEGV: "SIGSEGV", SIGPIPE: "SIGPIPE", SIGALRM: "SIGALRM",
    SIGTERM: "SIGTERM", SIGUSR1: "SIGUSR1", SIGUSR2: "SIGUSR2",
  ]
}

/// The final state of a supervised process once its direct child exited and the
/// output pipes drained.
public struct ProcessExit: Equatable, Sendable {
  public var termination: ProcessTermination
  public var standardOutput: Data
  public var standardError: Data
  public var isStandardOutputTruncated: Bool
  public var isStandardErrorTruncated: Bool
  /// Lines dropped from the `output` stream because its consumer fell behind.
  public var droppedOutputLineCount: Int
}

/// The outcome of `SupervisedProcess.wait(timeout:)`.
public enum ProcessCompletion: Equatable, Sendable {
  case exited(ProcessExit)
  /// The timeout elapsed; the process tree is being terminated in the background.
  case timedOut
  /// The waiting task was cancelled; the process tree is being terminated in the background.
  case cancelled
}

public enum ProcessOutputStream: Hashable, Sendable {
  case standardOutput
  case standardError
}

/// Complete lines decoded from one read of a child's pipe.
public struct ProcessOutputChunk: Equatable, Sendable {
  public var stream: ProcessOutputStream
  public var lines: [String]

  public init(stream: ProcessOutputStream, lines: [String]) {
    self.stream = stream
    self.lines = lines
  }
}

public enum ProcessSupervisorError: LocalizedError, Equatable {
  case unsupportedPlatform
  case launchFailed(executable: String, message: String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedPlatform:
      "Running commands is not available on this platform."
    case .launchFailed(let executable, let message):
      "Could not launch \(executable): \(message)"
    }
  }
}
