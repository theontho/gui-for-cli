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

  public static func expand(_ path: String, rootURL: URL, configURL: URL? = nil) -> String {
    let home = NSHomeDirectory()
    let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "\(home)/.config"
    let applicationSupport =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
      ?? "\(home)/Library/Application Support"
    let configPath = configURL?.path ?? ""
    let configDir = configURL?.deletingLastPathComponent().path ?? ""

    return
      path
      .replacingOccurrences(of: "{{bundleRoot}}", with: rootURL.path)
      .replacingOccurrences(of: "{{bundleWorkspace}}", with: rootURL.path)
      .replacingOccurrences(of: "{{home}}", with: home)
      .replacingOccurrences(of: "{{configHome}}", with: configHome)
      .replacingOccurrences(of: "{{userConfig}}", with: configHome)
      .replacingOccurrences(of: "{{applicationSupport}}", with: applicationSupport)
      .replacingOccurrences(of: "{{appConfig}}", with: applicationSupport)
      .replacingOccurrences(of: "{{configPath}}", with: configPath)
      .replacingOccurrences(of: "{{configDir}}", with: configDir)
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

public enum ConfigBootstrapError: LocalizedError, Equatable {
  case unsafeScriptPath(String)
  case missingScript(URL)
  case scriptFailed(URL, Int32, String)
  case invalidScriptOutput(URL, String)
  case missingScriptContents(URL)
  case unsupportedScriptPlatform

  public var errorDescription: String? {
    switch self {
    case .unsafeScriptPath(let path):
      "Config bootstrap script path must be relative and stay inside the bundle: \(path)"
    case .missingScript(let url):
      "Config bootstrap script does not exist: \(url.path)"
    case .scriptFailed(let url, let status, let output):
      "Config bootstrap script failed with exit code \(status): \(url.path)\n\(output)"
    case .invalidScriptOutput(let url, let output):
      "Config bootstrap script did not return valid JSON: \(url.path)\n\(output)"
    case .missingScriptContents(let url):
      "Config bootstrap script contents file does not exist: \(url.path)"
    case .unsupportedScriptPlatform:
      "Config bootstrap scripts are only available on macOS."
    }
  }
}

private struct ScriptBootstrapPayload: Codable {
  var path: String?
  var contents: String?
  var contentsPath: String?
  var values: [String: String]?
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
          rootURL: rootURL,
          script: bootstrapSpec.script,
          dryRun: dryRun))
    }
    return results
  }

  private func bootstrap(
    control: ControlSpec,
    configFile: ConfigFileSpec,
    mode: ConfigBootstrapMode,
    url: URL,
    rootURL: URL,
    script: ConfigBootstrapScriptSpec?,
    dryRun: Bool
  ) throws -> ConfigBootstrapResult {
    switch configFile.format {
    case .toml:
      let document = try bootstrapDocument(
        control: control,
        rootURL: rootURL,
        defaultURL: url,
        script: script,
        dryRun: dryRun)
      return try bootstrapToml(
        control: control,
        mode: mode,
        url: document.url,
        contents: document.contents,
        dryRun: dryRun)
    }
  }

  private func bootstrapDocument(
    control: ControlSpec,
    rootURL: URL,
    defaultURL: URL,
    script: ConfigBootstrapScriptSpec?,
    dryRun: Bool
  ) throws -> (url: URL, contents: String) {
    guard let script else {
      return (
        defaultURL, FlatTomlDocument.string(from: control.settings.map { ($0.key, $0.value ?? "") })
      )
    }

    let payload = try runScript(
      script,
      control: control,
      rootURL: rootURL,
      defaultURL: defaultURL,
      dryRun: dryRun)
    let payloadPath = payload.path?.trimmingCharacters(in: .whitespacesAndNewlines)
    let url =
      if let payloadPath, !payloadPath.isEmpty {
        BundlePathResolver.resolveConfigFilePath(payloadPath, rootURL: rootURL)
      } else {
        defaultURL
      }
    let contents = try scriptContents(from: payload, rootURL: rootURL)
    return (url, contents)
  }

  private func bootstrapToml(
    control: ControlSpec,
    mode: ConfigBootstrapMode,
    url: URL,
    contents: String,
    dryRun: Bool
  ) throws -> ConfigBootstrapResult {
    let exists = fileManager.fileExists(atPath: url.path)
    let defaultValues = try FlatTomlDocument.parse(contents)

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
        try contents.write(to: url, atomically: true, encoding: .utf8)
      }
      return ConfigBootstrapResult(
        controlID: control.id,
        label: control.label,
        url: url,
        status: dryRun ? .wouldCreate : .created,
        keyCount: defaultValues.count)
    case .mergeMissing:
      let existing =
        exists
        ? try FlatTomlDocument.parse(String(contentsOf: url, encoding: .utf8))
        : [:]
      let missing = defaultValues.filter { existing[$0.key] == nil }
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

  private func scriptContents(from payload: ScriptBootstrapPayload, rootURL: URL) throws -> String {
    if let contents = payload.contents {
      return contents
    }
    if let contentsPath = payload.contentsPath?.trimmingCharacters(in: .whitespacesAndNewlines),
      !contentsPath.isEmpty
    {
      let url = BundlePathResolver.resolveConfigFilePath(contentsPath, rootURL: rootURL)
      guard fileManager.fileExists(atPath: url.path) else {
        throw ConfigBootstrapError.missingScriptContents(url)
      }
      return try String(contentsOf: url, encoding: .utf8)
    }
    if let values = payload.values {
      return FlatTomlDocument.string(from: values)
    }
    return ""
  }

  private func runScript(
    _ script: ConfigBootstrapScriptSpec,
    control: ControlSpec,
    rootURL: URL,
    defaultURL: URL,
    dryRun: Bool
  ) throws -> ScriptBootstrapPayload {
    #if os(macOS)
      let scriptURL = try resolveBundledPath(script.path, rootURL: rootURL, mustExist: true)
      let workingDirectory = try resolveBundledPath(
        script.workingDirectory ?? "", rootURL: rootURL, mustExist: false)
      let output = Pipe()
      let error = Pipe()
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/sh")
      process.arguments =
        [scriptURL.path]
        + script.arguments.map {
          BundlePathResolver.expand($0, rootURL: rootURL, configURL: defaultURL)
        }
      process.currentDirectoryURL = workingDirectory
      process.standardOutput = output
      process.standardError = error
      process.environment = scriptEnvironment(
        script: script,
        control: control,
        rootURL: rootURL,
        defaultURL: defaultURL,
        dryRun: dryRun)
      try process.run()
      process.waitUntilExit()

      let outputText =
        String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      let errorText =
        String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      guard process.terminationStatus == 0 else {
        throw ConfigBootstrapError.scriptFailed(
          scriptURL,
          process.terminationStatus,
          [outputText, errorText].filter { !$0.isEmpty }.joined(separator: "\n"))
      }
      let trimmed = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let data = trimmed.data(using: .utf8),
        let payload = try? JSONDecoder().decode(ScriptBootstrapPayload.self, from: data)
      else {
        throw ConfigBootstrapError.invalidScriptOutput(scriptURL, outputText)
      }
      return payload
    #else
      throw ConfigBootstrapError.unsupportedScriptPlatform
    #endif
  }

  private func scriptEnvironment(
    script: ConfigBootstrapScriptSpec,
    control: ControlSpec,
    rootURL: URL,
    defaultURL: URL,
    dryRun: Bool
  ) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment.merge(
      [
        "GUI_FOR_CLI_BUNDLE_ROOT": rootURL.path,
        "GUI_FOR_CLI_BUNDLE_WORKSPACE": rootURL.path,
        "GUI_FOR_CLI_CONFIG_PATH": defaultURL.path,
        "GUI_FOR_CLI_CONFIG_DIR": defaultURL.deletingLastPathComponent().path,
        "GUI_FOR_CLI_CONFIG_CONTROL_ID": control.id,
        "GUI_FOR_CLI_CONFIG_CONTROL_LABEL": control.label,
        "GUI_FOR_CLI_DRY_RUN": dryRun ? "1" : "0",
      ]
    ) { _, new in new }
    environment.merge(
      script.environment.mapValues {
        BundlePathResolver.expand($0, rootURL: rootURL, configURL: defaultURL)
      }
    ) { _, new in new }
    return environment
  }

  private func resolveBundledPath(_ path: String, rootURL: URL, mustExist: Bool) throws -> URL {
    guard !path.isEmpty else { return rootURL }
    let nsPath = path as NSString
    guard !nsPath.isAbsolutePath, !path.split(separator: "/").contains("..") else {
      throw ConfigBootstrapError.unsafeScriptPath(path)
    }
    let root = rootURL.standardizedFileURL
    let candidate = root.appendingPathComponent(path).standardizedFileURL
    guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
      throw ConfigBootstrapError.unsafeScriptPath(path)
    }
    if mustExist, !fileManager.fileExists(atPath: candidate.path) {
      throw ConfigBootstrapError.missingScript(candidate)
    }
    return candidate
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
