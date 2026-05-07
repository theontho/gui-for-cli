import ArgumentParser
import Foundation
import GUIForCLICore

struct BundleCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "bundle",
    abstract: "Inspect and create GUI-for-CLI bundles.",
    subcommands: [Inspect.self, Setup.self, WriteDemo.self]
  )
}

extension BundleCommand {
  struct Inspect: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Load a bundle and print its pages.")

    @OptionGroup var options: GlobalOptions
    @Argument(help: "Path to a bundle folder, manifest.json, or supported archive.") var path:
      String

    mutating func run() throws {
      try options.validate()
      let loaded = try BundleSourceLoader().load(from: URL(fileURLWithPath: path))

      CLIOutput.line("\(loaded.manifest.displayName) (\(loaded.manifest.id))", quiet: options.quiet)
      CLIOutput.line("Manifest: \(loaded.manifestURL.path)", quiet: options.quiet)
      CLIOutput.line("Pages:", quiet: options.quiet)
      for page in loaded.manifest.pages {
        CLIOutput.line("  - \(page.title) [\(page.id)]", quiet: options.quiet)
      }
      if !loaded.manifest.setup.steps.isEmpty {
        CLIOutput.line("Setup:", quiet: options.quiet)
        let commands = try SetupCommandPlanner(requireScriptFiles: false).plan(
          for: loaded.manifest, rootURL: loaded.rootURL)
        for command in commands {
          CLIOutput.line(
            "  - \(command.kind.rawValue): \(command.displayCommand)", quiet: options.quiet)
        }
      }
    }
  }

  struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Run or preview bundle setup steps.")

    @OptionGroup var options: GlobalOptions
    @Flag(help: "Print setup commands without running them.") var dryRun = false
    @Argument(help: "Path to a bundle folder, manifest.json, or supported archive.") var path:
      String

    mutating func run() throws {
      try options.validate()
      let loaded = try BundleSourceLoader().load(from: URL(fileURLWithPath: path))
      let commands = try SetupCommandPlanner(requireScriptFiles: !dryRun).plan(
        for: loaded.manifest, rootURL: loaded.rootURL)
      let runner = SetupCommandRunner()

      for command in commands {
        CLIOutput.line("==> \(command.label)", quiet: options.quiet)
        CLIOutput.line("$ \(command.displayCommand)", quiet: options.quiet)
        if dryRun { continue }

        let result = try runner.run(command)
        if !result.output.isEmpty {
          CLIOutput.line(result.output.trimmingCharacters(in: .newlines), quiet: options.quiet)
        }
        if result.exitStatus != 0 && !command.optional {
          throw ExitCode(result.exitStatus)
        }
        if result.exitStatus != 0 && command.optional {
          CLIOutput.line(
            "Optional setup step failed with exit code \(result.exitStatus).", quiet: options.quiet)
        }
      }
    }
  }

  struct WriteDemo: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Write an example WGS Extract bundle manifest.")

    @OptionGroup var options: GlobalOptions
    @Flag(help: "Overwrite the output directory if it exists.") var force = false
    @Argument(help: "Destination directory for the example bundle.") var path: String

    mutating func run() throws {
      try options.validate()
      let destinationURL = URL(fileURLWithPath: path)
      try BundleSourceLoader().writeDemoBundle(to: destinationURL, overwrite: force)
      CLIOutput.line("Wrote demo bundle to \(destinationURL.path)", quiet: options.quiet)
    }
  }
}
