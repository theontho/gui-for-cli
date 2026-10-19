import ArgumentParser
import Foundation
import GUIForCLICore

@main
struct GUIForCLICLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "gui-for-cli",
    abstract: "Prototype CLI companion for the GUI-for-CLI bundle renderer.",
    version: "0.1.0",
    subcommands: [Precheck.self, ConfigCommand.self, BundleCommand.self, Run.self],
    defaultSubcommand: Run.self
  )
}

extension GUIForCLICLI {
  static func main() async {
    await CLITermination.run(Self.self)
  }
}
