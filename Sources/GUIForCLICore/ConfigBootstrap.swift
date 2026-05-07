import Foundation

public enum BundlePathResolver {
  public static func resolveConfigFilePath(_ path: String, rootURL: URL) -> URL {
    let expanded = expand(path, rootURL: rootURL)
    let nsPath = expanded as NSString
    if nsPath.isAbsolutePath {
      return URL(fileURLWithPath: expanded, isDirectory: false)
    }
    return rootURL.appendingPathComponent(expanded, isDirectory: false)
  }

  private static func expand(_ path: String, rootURL: URL) -> String {
    let home = NSHomeDirectory()
    let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "\(home)/.config"
    let applicationSupport =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
      ?? "\(home)/Library/Application Support"

    return
      path
      .replacingOccurrences(of: "{{bundleRoot}}", with: rootURL.path)
      .replacingOccurrences(of: "{{home}}", with: home)
      .replacingOccurrences(of: "{{configHome}}", with: configHome)
      .replacingOccurrences(of: "{{applicationSupport}}", with: applicationSupport)
      .replacingOccurrences(of: "~/", with: "\(home)/", options: [.anchored])
  }
}

public enum FlatTomlDocument {
  public static func parse(_ text: String) throws -> [String: String] {
    var values: [String: String] = [:]
    for rawLine in text.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty || line.hasPrefix("#") || !line.contains("=") {
        continue
      }
      let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let key = String(parts[0])
        .trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
      let rawValue = String(parts[1]).trimmingCharacters(in: .whitespaces)
      values[key] = parseValue(rawValue)
    }
    return values
  }

  public static func string(from pairs: [(String, String)]) -> String {
    pairs.map { key, value in "\(tomlKey(key)) = \(tomlValue(value))" }
      .joined(separator: "\n") + "\n"
  }

  public static func string(from values: [String: String]) -> String {
    string(from: values.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
  }

  private static func parseValue(_ value: String) -> String {
    guard value.hasPrefix("\""), value.hasSuffix("\"") else {
      return value
    }
    var result = ""
    var iterator = value.dropFirst().dropLast().makeIterator()
    while let character = iterator.next() {
      guard character == "\\" else {
        result.append(character)
        continue
      }
      guard let escaped = iterator.next() else { break }
      switch escaped {
      case "n": result.append("\n")
      case "r": result.append("\r")
      case "t": result.append("\t")
      case "\"": result.append("\"")
      case "\\": result.append("\\")
      default: result.append(escaped)
      }
    }
    return result
  }

  private static func tomlKey(_ key: String) -> String {
    if key.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
      return key
    }
    return tomlValue(key)
  }

  private static func tomlValue(_ value: String) -> String {
    "\""
      + value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n") + "\""
  }
}

public struct ConfigBootstrapResult: Equatable, Sendable {
  public var controlID: String
  public var label: String
  public var url: URL
  public var status: ConfigBootstrapStatus
  public var keyCount: Int

  public init(
    controlID: String,
    label: String,
    url: URL,
    status: ConfigBootstrapStatus,
    keyCount: Int
  ) {
    self.controlID = controlID
    self.label = label
    self.url = url
    self.status = status
    self.keyCount = keyCount
  }

  public var message: String {
    switch status {
    case .created:
      "Created \(keyCount) setting(s) at \(url.path)"
    case .merged:
      "Added \(keyCount) missing setting(s) to \(url.path)"
    case .skippedExisting:
      "Settings already exist at \(url.path)"
    case .unchanged:
      "Settings already contain all configured keys at \(url.path)"
    case .wouldCreate:
      "Would create \(keyCount) setting(s) at \(url.path)"
    case .wouldMerge:
      "Would add \(keyCount) missing setting(s) to \(url.path)"
    case .wouldSkipExisting:
      "Would leave existing settings at \(url.path)"
    case .wouldLeaveUnchanged:
      "Would leave complete settings unchanged at \(url.path)"
    }
  }
}

public enum ConfigBootstrapStatus: String, Equatable, Sendable {
  case created
  case merged
  case skippedExisting
  case unchanged
  case wouldCreate
  case wouldMerge
  case wouldSkipExisting
  case wouldLeaveUnchanged
}

public struct ConfigFileBootstrapper {
  public var fileManager: FileManager

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  public func bootstrap(
    manifest: CLIBundleManifest,
    rootURL: URL,
    pathOverrides: [String: String] = [:],
    dryRun: Bool = false
  ) throws -> [ConfigBootstrapResult] {
    var results: [ConfigBootstrapResult] = []
    for control in manifest.configEditorControls {
      guard let configFile = control.configFile, let bootstrapSpec = configFile.bootstrap,
        bootstrapSpec.mode != .none
      else {
        continue
      }
      let path = pathOverrides[control.id] ?? configFile.path
      let url = BundlePathResolver.resolveConfigFilePath(path, rootURL: rootURL)
      try results.append(
        bootstrap(
          control: control,
          configFile: configFile,
          mode: bootstrapSpec.mode,
          url: url,
          dryRun: dryRun))
    }
    return results
  }

  private func bootstrap(
    control: ControlSpec,
    configFile: ConfigFileSpec,
    mode: ConfigBootstrapMode,
    url: URL,
    dryRun: Bool
  ) throws -> ConfigBootstrapResult {
    switch configFile.format {
    case .toml:
      return try bootstrapToml(control: control, mode: mode, url: url, dryRun: dryRun)
    }
  }

  private func bootstrapToml(
    control: ControlSpec,
    mode: ConfigBootstrapMode,
    url: URL,
    dryRun: Bool
  ) throws -> ConfigBootstrapResult {
    let defaults = control.settings.map { ($0.key, $0.value ?? "") }
    let exists = fileManager.fileExists(atPath: url.path)

    switch mode {
    case .none:
      return ConfigBootstrapResult(
        controlID: control.id,
        label: control.label,
        url: url,
        status: dryRun ? .wouldLeaveUnchanged : .unchanged,
        keyCount: 0)
    case .createIfMissing:
      guard !exists else {
        return ConfigBootstrapResult(
          controlID: control.id,
          label: control.label,
          url: url,
          status: dryRun ? .wouldSkipExisting : .skippedExisting,
          keyCount: 0)
      }
      if !dryRun {
        try fileManager.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FlatTomlDocument.string(from: defaults).write(
          to: url, atomically: true, encoding: .utf8)
      }
      return ConfigBootstrapResult(
        controlID: control.id,
        label: control.label,
        url: url,
        status: dryRun ? .wouldCreate : .created,
        keyCount: defaults.count)
    case .mergeMissing:
      let existing =
        exists
        ? try FlatTomlDocument.parse(String(contentsOf: url, encoding: .utf8))
        : [:]
      let missing = defaults.filter { existing[$0.0] == nil }
      guard !missing.isEmpty else {
        return ConfigBootstrapResult(
          controlID: control.id,
          label: control.label,
          url: url,
          status: dryRun ? .wouldLeaveUnchanged : .unchanged,
          keyCount: 0)
      }
      if !dryRun {
        var merged = existing
        for (key, value) in missing {
          merged[key] = value
        }
        try fileManager.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FlatTomlDocument.string(from: merged).write(to: url, atomically: true, encoding: .utf8)
      }
      return ConfigBootstrapResult(
        controlID: control.id,
        label: control.label,
        url: url,
        status: dryRun ? .wouldMerge : .merged,
        keyCount: missing.count)
    }
  }
}

public extension CLIBundleManifest {
  var configEditorControls: [ControlSpec] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
      .filter { $0.kind == .configEditor }
  }
}
