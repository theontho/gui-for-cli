import ArgumentParser
import Foundation
import GUIForCLICore

struct ConfigCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "config",
    abstract: "Manage configuration.",
    subcommands: [Show.self, Init.self]
  )
}

extension ConfigCommand {
  struct Show: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show the current configuration.")

    @OptionGroup var options: GlobalOptions

    mutating func run() throws {
      try options.validate()
      let store = AppConfigStore()
      let config = try store.load()

      CLIOutput.line("Configuration (\(store.path.path)):", quiet: options.quiet)
      for item in config.redactedValues() {
        CLIOutput.line("  \(item.key): \(item.value)", quiet: options.quiet)
      }
    }
  }

  struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Initialize default configuration.")

    @OptionGroup var options: GlobalOptions
    @Flag(help: "Overwrite an existing config file.") var force = false

    mutating func run() throws {
      try options.validate()
      let store = AppConfigStore()
      _ = try store.initializeDefault(force: force)
      CLIOutput.line("Initialized config at \(store.path.path)", quiet: options.quiet)
    }
  }
}
