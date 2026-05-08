import ArgumentParser
import Foundation
import GUIForCLICore

struct BundleCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "bundle",
    abstract: "Inspect and create GUI-for-CLI bundles.",
    subcommands: [Inspect.self, Setup.self, Validate.self, WriteDemo.self]
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

private struct BundleSummary {
  let lines: [String]
  init(loaded: LoadedBundle) {
    var lines: [String] = []
    let manifest = loaded.manifest
    lines.append("\(manifest.displayName) (\(manifest.id))")
    lines.append("  pages: \(manifest.pages.count)")
    for page in manifest.pages {
      let sectionCount = page.sections.count
      let actionCount = page.sections.reduce(0) { $0 + $1.actions.count }
      let controlCount = page.sections.reduce(0) { $0 + $1.controls.count }
      lines.append(
        "    - \(page.id): sections=\(sectionCount) controls=\(controlCount) actions=\(actionCount)"
      )
    }
    if !manifest.exitCodeReference.isEmpty {
      lines.append("  exit-code entries: \(manifest.exitCodeReference.count)")
    }
    if !manifest.setup.steps.isEmpty {
      lines.append("  setup steps: \(manifest.setup.steps.count)")
    }
    lines.append("  locales: \(loaded.localizationOptions.count)")
    self.lines = lines
  }
}

private enum LocaleLinterRunner {
  struct Result {
    var errors: Int
    var warnings: Int
  }

  static func run(bundleRoot: URL, strict: Bool, quiet: Bool) throws -> Result {
    let scriptURL = repoRootSearch(from: bundleRoot)?
      .appendingPathComponent("scripts/lint-locales.swift")
    guard let scriptURL, FileManager.default.fileExists(atPath: scriptURL.path) else {
      // Linter unavailable — treat as a no-op rather than a failure.
      if !quiet {
        CLIOutput.line("  (locale linter not found; skipping)", quiet: false)
      }
      return Result(errors: 0, warnings: 0)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    var arguments = ["swift", scriptURL.path]
    if strict { arguments.append("--strict") }
    arguments.append(bundleRoot.path)
    process.arguments = arguments
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    let combined =
      (String(data: outData, encoding: .utf8) ?? "")
      + (String(data: errData, encoding: .utf8) ?? "")
    if !quiet {
      let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        CLIOutput.line(trimmed, quiet: false)
      }
    }
    let errors = combined.matchCount(of: ", \\d+ errors")
    let warnings = combined.matchCount(of: ", \\d+ warnings")
    return Result(
      errors: process.terminationStatus == 0 ? 0 : (errors > 0 ? errors : 1),
      warnings: warnings)
  }

  private static func repoRootSearch(from start: URL) -> URL? {
    var url = start
    for _ in 0..<8 {
      if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
        return url
      }
      let parent = url.deletingLastPathComponent()
      if parent.path == url.path { break }
      url = parent
    }
    return nil
  }
}

private extension String {
  func matchCount(of pattern: String) -> Int {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
    return regex.numberOfMatches(in: self, range: NSRange(startIndex..<endIndex, in: self))
  }
}
