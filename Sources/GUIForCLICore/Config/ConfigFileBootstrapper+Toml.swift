import Foundation

struct ScriptBootstrapPayload: Codable {
  var path: String?
  var contents: String?
  var contentsPath: String?
  var values: [String: String]?
}

extension ConfigFileBootstrapper {
  func bootstrapDocument(
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

  func bootstrapToml(
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

  func scriptContents(from payload: ScriptBootstrapPayload, rootURL: URL) throws -> String {
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
}
