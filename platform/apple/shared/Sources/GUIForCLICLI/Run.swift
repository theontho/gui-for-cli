import ArgumentParser
import Foundation
import GUIForCLICore

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
