import Foundation

public struct SetupCommandPlanner: Sendable {
  private let requireScriptFiles: Bool

  public init(requireScriptFiles: Bool = true) {
    self.requireScriptFiles = requireScriptFiles
  }

  public func plan(for manifest: CLIBundleManifest, rootURL: URL) throws -> [SetupCommand] {
    try manifest.setup.steps.filter { $0.applies() }.map { step in
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
      let scriptURL = try resolveFile(
        BundlePlatformScriptResolver.resolve(step.value, rootURL: rootURL).path,
        rootURL: rootURL)
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
    if nsPath.isAbsolutePath {
      let candidate = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
      let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
      guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
        throw SetupPlanError.unsafeRelativePath(path)
      }
      if mustExist, !FileManager.default.fileExists(atPath: candidate.path) {
        throw SetupPlanError.missingScript(candidate)
      }
      return candidate
    }
    guard !path.split(separator: "/").contains("..") else {
      throw SetupPlanError.unsafeRelativePath(path)
    }

    let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    let candidate = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
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
