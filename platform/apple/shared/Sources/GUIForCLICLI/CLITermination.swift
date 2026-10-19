import ArgumentParser
import Foundation
import GUIForCLICore

/// Children run in their own process groups, so a terminal's Ctrl-C reaches
/// only the CLI. SIGINT/SIGTERM terminate every supervised tree, and the CLI
/// then exits with the shell status for the signal (130 for SIGINT).
enum CLITermination {
  /// Lock-guarded: the received signal, and the installed sources (kept alive).
  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var signal: Int32?
    var sources: [any DispatchSourceSignal] = []
  }

  private static let state = State()

  private static func installSignalForwarding() {
    let sources = [SIGINT, SIGTERM].map { signalNumber in
      signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
      source.setEventHandler {
        // Held until the trees are gone, so the main path cannot exit first.
        state.lock.lock()
        state.signal = signalNumber
        ProcessSupervisor.shared.terminateAll(waitingUpTo: .seconds(2))
        exit(128 + signalNumber)
      }
      source.resume()
      return source
    }
    state.lock.withLock { state.sources = sources }
  }

  /// Parses and runs the CLI with interrupt forwarding installed.
  static func run(_ command: GUIForCLICLI.Type) async {
    installSignalForwarding()
    do {
      var parsed = try command.parseAsRoot()
      if var asyncCommand = parsed as? any AsyncParsableCommand {
        try await asyncCommand.run()
      } else {
        try parsed.run()
      }
    } catch {
      exitIfInterrupted()
      command.exit(withError: error)
    }
    exitIfInterrupted()
  }

  private static func exitIfInterrupted() {
    state.lock.lock()
    let signalNumber = state.signal
    state.lock.unlock()
    if let signalNumber {
      exit(128 + signalNumber)
    }
  }
}
