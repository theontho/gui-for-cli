import ArgumentParser
import Foundation
import GUIForCLICore

@main
struct GUIForCLICLI: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "gui-for-cli",
    abstract: "Prototype CLI companion for the GUI-for-CLI bundle renderer.",
    version: "0.1.0",
    subcommands: [Precheck.self, ConfigCommand.self, BundleCommand.self, Run.self],
    defaultSubcommand: Run.self
  )
}

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

enum CLIOutput {
  static func line(_ message: String, quiet: Bool = false) {
    if !quiet { print(message) }
  }

  static func log(
    _ message: String, level: LogLevel, configuredLevel: LogLevel, quiet: Bool = false
  ) {
    guard level.severity >= configuredLevel.severity else { return }
    if quiet && level != .error { return }

    let stream = level == .error ? FileHandle.standardError : FileHandle.standardOutput
    if let data = "[\(level.rawValue)] \(message)\n".data(using: .utf8) {
      stream.write(data)
    }
  }
}

struct Run: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Run the main application logic.")

  @OptionGroup var options: GlobalOptions
  @Option(help: "Name to greet.") var name = "World"

  mutating func run() throws {
    try options.validate()
    let store = AppConfigStore()
    let config = try store.load()
    let logLevel = options.resolvedLogLevel(config: config)

    CLIOutput.log(
      "Debug logging is enabled", level: .debug, configuredLevel: logLevel, quiet: options.quiet)
    CLIOutput.log(
      "Starting gui-for-cli", level: .info, configuredLevel: logLevel, quiet: options.quiet)
    CLIOutput.line(Self.greeting(name: name), quiet: options.quiet)
    CLIOutput.line("Data directory: \(config.dataDirectory)", quiet: options.quiet)
  }

  static func greeting(name: String) -> String {
    "Hello, \(name) from gui-for-cli!"
  }
}
