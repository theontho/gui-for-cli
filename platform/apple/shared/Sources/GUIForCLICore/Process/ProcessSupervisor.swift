import Foundation

/// The one place bundle commands are launched from. Tracks every live process
/// tree app-wide so they can all be terminated on quit.
public final class ProcessSupervisor: @unchecked Sendable {
  public static let shared = ProcessSupervisor()

  private let lock = NSLock()
  private var processes: [UUID: SupervisedProcess] = [:]

  public init() {}

  public func launch(_ request: ProcessRequest) throws -> SupervisedProcess {
    #if os(macOS) || os(Linux)
      try SupervisedProcess.launch(
        request,
        register: { process in lock.withLock { processes[process.id] = process } },
        onSettled: { [weak self] process in self?.remove(process) })
    #else
      throw ProcessSupervisorError.unsupportedPlatform
    #endif
  }

  /// Processes that are running, or whose tree is still being terminated.
  public var activeProcesses: [SupervisedProcess] {
    lock.withLock { Array(processes.values) }
  }

  /// Starts terminating every tracked process tree. Returns immediately.
  public func terminateAll() {
    for process in activeProcesses {
      process.terminate()
    }
  }

  /// Terminates every tracked process tree and blocks until they are gone,
  /// sending SIGKILL to any group still alive after `timeout`. For app quit.
  public func terminateAll(waitingUpTo timeout: Duration) {
    let processes = activeProcesses
    for process in processes {
      process.signalGroup(SIGTERM)
      process.terminate()
    }
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline, processes.contains(where: \.isGroupAlive) {
      usleep(10_000)
    }
    for process in processes where process.isGroupAlive {
      process.signalGroup(SIGKILL)
    }
  }

  private func remove(_ process: SupervisedProcess) {
    _ = lock.withLock { processes.removeValue(forKey: process.id) }
  }
}
