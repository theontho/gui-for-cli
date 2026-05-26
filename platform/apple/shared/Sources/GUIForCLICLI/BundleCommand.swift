import ArgumentParser
import Foundation
import GUIForCLICore

struct BundleCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "bundle",
    abstract: "Inspect and create GUI-for-CLI bundles.",
    subcommands: [Inspect.self, Setup.self, Test.self, Validate.self, WriteDemo.self]
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
      let setupCommands = try SetupCommandPlanner(requireScriptFiles: false).plan(
        for: loaded.manifest, rootURL: loaded.rootURL)
      if !setupCommands.isEmpty {
        CLIOutput.line("Setup:", quiet: options.quiet)
        for command in setupCommands {
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
      let bootstrapResults = try ConfigFileBootstrapper().bootstrap(
        manifest: loaded.manifest,
        rootURL: loaded.rootURL,
        dryRun: dryRun)
      let commands = try SetupCommandPlanner(requireScriptFiles: !dryRun).plan(
        for: loaded.manifest, rootURL: loaded.rootURL)
      let runner = SetupCommandRunner()

      for result in bootstrapResults {
        CLIOutput.line("==> \(result.label)", quiet: options.quiet)
        CLIOutput.line(result.message, quiet: options.quiet)
      }

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

  struct Test: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Run a bundle action test plan and write a JSON report.")

    @OptionGroup var options: GlobalOptions
    @Option(help: "Path to a JSON bundle test plan.")
    var plan: String?
    @Option(help: "Write the JSON report to this path.")
    var report: String?
    @Option(help: "Write the live bundle test console log to this path.")
    var log: String?
    @Option(help: "Use this bundle workspace directory for the test run.")
    var workspace: String?
    @Flag(help: "Render setup and action commands without executing them.")
    var dryRun = false
    @Flag(help: "Run bundle setup before any --action steps.")
    var runSetup = false
    @Option(help: "Action id to run. Repeat to run multiple actions after optional setup.")
    var action: [String] = []
    @Option(
      name: .customLong("input"),
      help: "Set an input field as key=value. Repeat for multiple inputs.")
    var fieldInput: [String] = []
    @Option(
      name: .customLong("config"),
      help: "Set a config value as key=value. Repeat for multiple config values.")
    var configInput: [String] = []
    @Option(
      name: .customLong("checked"),
      help: "Set checkbox selections as key=value1,value2. Repeat for multiple controls.")
    var checkedInput: [String] = []
    @Argument(help: "Path to a bundle folder, manifest.json, or supported archive.")
    var path: String

    mutating func run() throws {
      try options.validate()
      var testPlan = try loadPlan()
      testPlan.inputs = testPlan.inputs.merging(try cliInputs())
      testPlan.steps += cliSteps()
      guard !testPlan.steps.isEmpty else {
        throw ValidationError("Provide --plan, --run-setup, or at least one --action.")
      }

      let runner = BundleTestRunner()
      let quiet = options.quiet
      let stamp = Self.runStamp()
      let reportURL = URL(fileURLWithPath: report ?? Self.defaultReportPath(stamp: stamp))
      let logURL = URL(fileURLWithPath: log ?? Self.defaultLogPath(stamp: stamp))
      let logWriter = try BundleTestLogWriter(url: logURL)
      defer { logWriter.close() }
      let result = try runner.run(
        bundleURL: URL(fileURLWithPath: path),
        plan: testPlan,
        options: BundleTestRunnerOptions(
          workspaceURL: workspace.map { URL(fileURLWithPath: $0, isDirectory: true) },
          dryRun: dryRun,
          progressHandler: { event in
            switch event {
            case .message(let message):
              logWriter.line(message)
              CLIOutput.line(message, quiet: quiet)
            case .commandOutput(let text):
              logWriter.write(text)
              CLIOutput.write(text, quiet: quiet)
            }
          }))
      try writeReport(result, to: reportURL)

      let summary =
        "Bundle test \(result.status.rawValue): \(result.summary.passed) passed, \(result.summary.failed) failed, \(result.summary.skipped) skipped."
      logWriter.line(summary)
      logWriter.line("Report: \(reportURL.path)")
      logWriter.line("Log: \(logURL.path)")
      CLIOutput.line(summary, quiet: options.quiet)
      CLIOutput.line("Report: \(reportURL.path)", quiet: options.quiet)
      CLIOutput.line("Log: \(logURL.path)", quiet: options.quiet)
      if result.status == .failed {
        throw ExitCode(1)
      }
    }

    private func loadPlan() throws -> BundleTestPlan {
      guard let plan else {
        return BundleTestPlan(steps: [])
      }
      let data = try Data(contentsOf: URL(fileURLWithPath: plan))
      return try JSONDecoder().decode(BundleTestPlan.self, from: data)
    }

    private func cliInputs() throws -> BundleTestInputs {
      BundleTestInputs(
        fieldValues: try Self.parseKeyValues(fieldInput, optionName: "--input"),
        configValues: try Self.parseKeyValues(configInput, optionName: "--config"),
        checkedOptions: try Self.parseCheckedValues(checkedInput))
    }

    private func cliSteps() -> [BundleTestStep] {
      var steps: [BundleTestStep] = []
      if runSetup {
        steps.append(BundleTestStep(kind: .setup))
      }
      steps += action.map { BundleTestStep(kind: .action, actionID: $0) }
      return steps
    }

    private func writeReport(_ report: BundleTestReport, to url: URL) throws {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(report).write(to: url, options: .atomic)
    }

    private static func parseKeyValues(_ values: [String], optionName: String) throws
      -> [String: String]
    {
      try values.reduce(into: [:]) { result, raw in
        let pair = try parseKeyValue(raw, optionName: optionName)
        result[pair.key] = pair.value
      }
    }

    private static func parseCheckedValues(_ values: [String]) throws -> [String: [String]] {
      try values.reduce(into: [:]) { result, raw in
        let pair = try parseKeyValue(raw, optionName: "--checked")
        result[pair.key] = pair.value.split(separator: ",").map {
          String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
      }
    }

    private static func parseKeyValue(_ raw: String, optionName: String) throws
      -> (key: String, value: String)
    {
      guard let separator = raw.firstIndex(of: "=") else {
        throw ValidationError("\(optionName) values must use key=value.")
      }
      let key = raw[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty else {
        throw ValidationError("\(optionName) values must include a non-empty key.")
      }
      let value = raw[raw.index(after: separator)...]
      return (String(key), String(value))
    }

    private static func runStamp() -> String {
      ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "-")
    }

    private static func defaultReportPath(stamp: String) -> String {
      return FileManager.default.currentDirectoryPath + "/bundle-test-report-\(stamp).json"
    }

    private static func defaultLogPath(stamp: String) -> String {
      return FileManager.default.currentDirectoryPath + "/bundle-test-log-\(stamp).log"
    }
  }

  private final class BundleTestLogWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle

    init(url: URL) throws {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      try Data().write(to: url, options: .atomic)
      handle = try FileHandle(forWritingTo: url)
    }

    func line(_ message: String) {
      write("\(message)\n")
    }

    func write(_ message: String) {
      guard let data = message.data(using: .utf8), !data.isEmpty else { return }
      lock.lock()
      handle.write(data)
      lock.unlock()
    }

    func close() {
      lock.lock()
      try? handle.close()
      lock.unlock()
    }
  }

  struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Validate a bundle manifest, pages, and string tables.")

    @OptionGroup var options: GlobalOptions
    @Flag(
      name: .long,
      help: "Treat untranslated strings and other warnings as errors (locale linter).")
    var strict = false
    @Flag(
      name: .long,
      help: "Skip the locale linter sub-step.")
    var skipLocales = false
    @Argument(help: "One or more bundle folders, manifest.json files, or supported archives.")
    var paths: [String]

    mutating func run() throws {
      try options.validate()
      guard !paths.isEmpty else {
        throw ValidationError("Provide at least one bundle path.")
      }
      var errorCount = 0
      var warningCount = 0
      for path in paths {
        let url = URL(fileURLWithPath: path)
        CLIOutput.line("==> \(url.path)", quiet: options.quiet)
        do {
          let loaded = try BundleSourceLoader().load(from: url)
          let summary = BundleSummary(loaded: loaded)
          if !options.quiet {
            for line in summary.lines {
              CLIOutput.line(line, quiet: false)
            }
          }
          if !skipLocales {
            let result = try LocaleLinterRunner.run(
              bundleRoot: loaded.rootURL, strict: strict, quiet: options.quiet)
            errorCount += result.errors
            warningCount += result.warnings
          }
        } catch {
          errorCount += 1
          CLIOutput.line("error: \(error.localizedDescription)", quiet: false)
        }
      }
      if errorCount > 0 || (strict && warningCount > 0) {
        throw ExitCode(1)
      }
    }
  }
}
