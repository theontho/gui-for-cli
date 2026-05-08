import ArgumentParser
import Foundation
import GUIForCLICore

struct GlobalOptions: ParsableArguments {
  @Flag(help: "Enable debug logging.") var debug = false
  @Flag(help: "Suppress all output except errors.") var quiet = false

  func validate() throws {
    if debug && quiet {
      throw ValidationError("Choose only one of --debug or --quiet.")
    }
  }

  func resolvedLogLevel(config: AppConfig) -> LogLevel {
    if quiet { return .error }
    if debug { return .debug }
    return config.logLevel
  }
}
