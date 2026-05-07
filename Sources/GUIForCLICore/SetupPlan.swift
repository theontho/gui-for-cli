import Foundation

public struct SetupCommand: Equatable, Identifiable, Sendable {
  public var id: String
  public var label: String
  public var kind: SetupStepKind
  public var executable: String
  public var arguments: [String]
  public var environment: [String: String]
  public var workingDirectory: URL
  public var optional: Bool

  public init(
    id: String,
    label: String,
    kind: SetupStepKind,
    executable: String,
    arguments: [String],
    environment: [String: String],
    workingDirectory: URL,
    optional: Bool
  ) {
    self.id = id
    self.label = label
    self.kind = kind
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.workingDirectory = workingDirectory
    self.optional = optional
  }

  public var displayCommand: String {
    ([executable] + arguments).map(Self.shellQuoted).joined(separator: " ")
  }

  private static func shellQuoted(_ value: String) -> String {
    guard !value.isEmpty, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
      !value.contains("'")
    else {
      return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
    return value
  }
}

public enum SetupPlanError: LocalizedError, Equatable {
  case unsafeRelativePath(String)
  case missingScript(URL)
  case unsupportedPlatform(String)

  public var errorDescription: String? {
    switch self {
    case .unsafeRelativePath(let path):
      "Setup path must be relative and stay inside the bundle: \(path)"
    case .missingScript(let url):
      "Setup script does not exist: \(url.path)"
    case .unsupportedPlatform(let platform):
      "Setup command execution is not available on \(platform)."
    }
  }
}

public struct SetupCommandPlanner: Sendable {
  private let requireScriptFiles: Bool

  public init(requireScriptFiles: Bool = true) {
    self.requireScriptFiles = requireScriptFiles
  }

  public func plan(for manifest: CLIBundleManifest, rootURL: URL) throws -> [SetupCommand] {
    try manifest.setup.steps.map { step in
      try command(for: step, rootURL: rootURL)
    }
  }

  private func command(for step: SetupStep, rootURL: URL) throws -> SetupCommand {
    let workingDirectory = try resolveDirectory(step.workingDirectory, rootURL: rootURL)
    let environment = step.environment.mapValues { expand($0, rootURL: rootURL) }
    let value = expand(step.value, rootURL: rootURL)
    let arguments = step.arguments.map { expand($0, rootURL: rootURL) }

    switch step.kind {
    case .pathTool:
      return SetupCommand(
        id: step.id,
        label: step.label,
        kind: step.kind,
        executable: "/usr/bin/env",
        arguments: ["which", value],
        environment: environment,
        workingDirectory: workingDirectory,
        optional: step.optional
      )
    case .homebrewPackage:
      return SetupCommand(
        id: step.id,
        label: step.label,
        kind: step.kind,
        executable: "/usr/bin/env",
        arguments: ["brew", "list", value],
        environment: environment,
        workingDirectory: workingDirectory,
        optional: step.optional
      )
    case .bundledScript, .setupScript:
      let scriptURL = try resolveFile(step.value, rootURL: rootURL)
      return SetupCommand(
        id: step.id,
        label: step.label,
        kind: step.kind,
        executable: "/bin/sh",
        arguments: [scriptURL.path] + arguments,
        environment: environment,
        workingDirectory: workingDirectory,
        optional: step.optional
      )
    case .pixiInstall:
      return SetupCommand(
        id: step.id,
        label: step.label,
        kind: step.kind,
        executable: "/usr/bin/env",
        arguments: ["pixi", "install"] + arguments,
        environment: environment,
        workingDirectory: workingDirectory,
        optional: step.optional
      )
    case .pixiRun:
      return SetupCommand(
        id: step.id,
        label: step.label,
        kind: step.kind,
        executable: "/usr/bin/env",
        arguments: ["pixi", "run", value] + arguments,
        environment: environment,
        workingDirectory: workingDirectory,
        optional: step.optional
      )
    }
  }

  private func resolveDirectory(_ path: String?, rootURL: URL) throws -> URL {
    guard let path, !path.isEmpty else { return rootURL }
    return try resolveRelative(path, rootURL: rootURL, mustExist: false)
  }

  private func resolveFile(_ path: String, rootURL: URL) throws -> URL {
    let url = try resolveRelative(path, rootURL: rootURL, mustExist: requireScriptFiles)
    if !requireScriptFiles {
      return url
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      throw SetupPlanError.missingScript(url)
    }
    return url
  }

  private func resolveRelative(_ path: String, rootURL: URL, mustExist: Bool) throws -> URL {
    let nsPath = path as NSString
    guard !nsPath.isAbsolutePath, !path.split(separator: "/").contains("..") else {
      throw SetupPlanError.unsafeRelativePath(path)
    }

    let root = rootURL.standardizedFileURL
    let candidate = root.appendingPathComponent(path).standardizedFileURL
    guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
      throw SetupPlanError.unsafeRelativePath(path)
    }
    if mustExist, !FileManager.default.fileExists(atPath: candidate.path) {
      throw SetupPlanError.missingScript(candidate)
    }
    return candidate
  }

  private func expand(_ value: String, rootURL: URL) -> String {
    value.replacingOccurrences(of: "{{bundleRoot}}", with: rootURL.path)
  }
}

public struct SetupCommandRunner: Sendable {
  public init() {}

  public func run(_ command: SetupCommand) throws -> CommandRunResult {
    #if os(macOS)
      let process = Process()
      let output = Pipe()
      process.executableURL = URL(fileURLWithPath: command.executable)
      process.arguments = command.arguments
      process.currentDirectoryURL = command.workingDirectory
      process.standardOutput = output
      process.standardError = output
      process.environment = ProcessInfo.processInfo.environment.merging(command.environment) {
        _, new in
        new
      }

      try process.run()
      process.waitUntilExit()

      let data = output.fileHandleForReading.readDataToEndOfFile()
      return CommandRunResult(
        exitStatus: process.terminationStatus,
        output: String(data: data, encoding: .utf8) ?? ""
      )
    #else
      throw SetupPlanError.unsupportedPlatform("this platform")
    #endif
  }
}

public struct CommandRunResult: Equatable, Sendable {
  public var exitStatus: Int32
  public var output: String
}
