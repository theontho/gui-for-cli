import Foundation

extension BundleSourceLoader {
  /// Best-effort match between a list of preferred locale identifiers (e.g. from the system) and
  /// the locale codes available in a bundle's `strings/` directory.
  ///
  /// Matching is performed in three passes for each preference:
  ///   1. Exact code match (e.g. `zh-Hant` -> `zh-Hant`).
  ///   2. Region-stripped match (e.g. `pt-BR` -> `pt`).
  ///   3. Script-aware Chinese fallback (e.g. `zh-CN` -> `zh-Hans`, `zh-TW` -> `zh-Hant`).
  ///
  /// Returns `nil` if no preference matches an available option.
  public static func matchLocalizationCode(
    preferences: [String],
    options: [BundleLocalizationOption]
  ) -> String? {
    let availableCodes = options.map { $0.code }
    let availableSet = Set(availableCodes)
    for raw in preferences {
      let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !candidate.isEmpty else { continue }
      if availableSet.contains(candidate) { return candidate }
      if let dash = candidate.firstIndex(of: "-") {
        let primary = String(candidate[..<dash])
        if availableSet.contains(primary) { return primary }
        if primary == "zh" {
          let region = candidate[candidate.index(after: dash)...].lowercased()
          if ["cn", "sg", "hans"].contains(where: region.contains)
            && availableSet.contains("zh-Hans")
          {
            return "zh-Hans"
          }
          if ["tw", "hk", "mo", "hant"].contains(where: region.contains)
            && availableSet.contains("zh-Hant")
          {
            return "zh-Hant"
          }
        }
      }
    }
    return nil
  }

  func loadStringTable(
    rootURL: URL,
    manifest: CLIBundleManifest,
    localizationCode: String
  ) throws -> BundleStringTable {
    var table = BuiltinStringTable.load(localizationCode: localizationCode)
    let defaultCode = manifest.defaultLocalizationCode
    if let baseURL = bundleStringsURL(rootURL: rootURL, code: defaultCode) {
      let baseTable = try BundleStringTable(tomlData: Data(contentsOf: baseURL))
      table = table.merging(baseTable)
    }
    if localizationCode != defaultCode,
      let localizedURL = bundleStringsURL(rootURL: rootURL, code: localizationCode),
      fileManager.fileExists(atPath: localizedURL.path)
    {
      let localizedTable = try BundleStringTable(tomlData: Data(contentsOf: localizedURL))
      table = table.merging(localizedTable)
    }
    return table
  }

  func loadLocalizationOptions(
    rootURL: URL, manifest: CLIBundleManifest
  ) throws -> [BundleLocalizationOption] {
    let defaultCode = manifest.defaultLocalizationCode
    var seen: [String: BundleLocalizationOption] = [:]

    for code in BuiltinStringTable.availableLocalizationCodes() {
      let displayName = BuiltinStringTable.displayName(for: code) ?? code
      seen[code] = BundleLocalizationOption(code: code, displayName: displayName)
    }

    if let stringsDirectory = bundleStringsDirectoryURL(rootURL: rootURL),
      fileManager.fileExists(atPath: stringsDirectory.path)
    {
      let children = try fileManager.contentsOfDirectory(
        at: stringsDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles])
      for url in children {
        guard let code = localizationCode(forStringsFileName: url.lastPathComponent) else {
          continue
        }
        let displayName =
          languageDisplayName(in: url) ?? seen[code]?.displayName ?? code
        seen[code] = BundleLocalizationOption(
          code: code,
          displayName: displayName,
          isAITranslated: languageAITranslatedFlag(in: url) ?? seen[code]?.isAITranslated ?? false)
      }
    }

    return seen.values.sorted { first, second in
      if first.code == defaultCode { return true }
      if second.code == defaultCode { return false }
      return first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
    }
  }

  func resolvedLocalizationCode(
    _ requestedLocalizationCode: String?,
    options: [BundleLocalizationOption],
    defaultCode: String
  ) -> String {
    let requested = requestedLocalizationCode?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let requested, !requested.isEmpty else {
      return defaultCode
    }
    guard options.contains(where: { $0.code == requested }) else {
      return defaultCode
    }
    return requested
  }

  /// Returns the URL of a bundle's `strings.<code>.toml` file inside its
  /// `strings/` subfolder, or `nil` if the bundle has no strings directory.
  func bundleStringsURL(rootURL: URL, code: String) -> URL? {
    guard code.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
      return nil
    }
    let url = bundleStringsDirectoryURL(rootURL: rootURL)?
      .appendingPathComponent("strings.\(code).toml", isDirectory: false)
    guard let url, fileManager.fileExists(atPath: url.path) else { return nil }
    return url
  }

  func bundleStringsDirectoryURL(rootURL: URL) -> URL? {
    rootURL.appendingPathComponent("strings", isDirectory: true)
  }

  func languageDisplayName(in stringsURL: URL) -> String? {
    languageStringValue(in: stringsURL, key: "language.name")
  }

  func languageAITranslatedFlag(in stringsURL: URL) -> Bool? {
    guard let value = languageStringValue(in: stringsURL, key: "language.aiTranslated") else {
      return nil
    }
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "true", "yes", "1":
      return true
    case "false", "no", "0":
      return false
    default:
      return nil
    }
  }

  func localizedLocalizationOptions(
    _ options: [BundleLocalizationOption],
    table: BundleStringTable
  ) -> [BundleLocalizationOption] {
    options.map { option in
      BundleLocalizationOption(
        code: option.code,
        displayName: table["language.names.\(option.code)"] ?? option.displayName,
        isAITranslated: option.isAITranslated)
    }
  }

  private func languageStringValue(in stringsURL: URL, key: String) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: stringsURL) else {
      return nil
    }
    defer {
      try? handle.close()
    }
    let prefix: Data?
    do {
      prefix = try handle.read(upToCount: 4096)
    } catch {
      return nil
    }
    guard let prefix, let text = String(data: prefix, encoding: .utf8) else {
      return nil
    }
    for line in text.split(whereSeparator: \.isNewline) {
      let trimmed = String(line).trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("\"\(key)\"") || trimmed.hasPrefix(key) else {
        continue
      }
      return try? FlatTomlDocument.parse(String(trimmed))[key]
    }
    return nil
  }

  func localizationCode(forStringsFileName fileName: String) -> String? {
    guard fileName.hasPrefix("strings."), fileName.hasSuffix(".toml") else {
      return nil
    }
    let start = fileName.index(fileName.startIndex, offsetBy: "strings.".count)
    let end = fileName.index(fileName.endIndex, offsetBy: -".toml".count)
    guard start < end else { return nil }
    let code = String(fileName[start..<end])
    guard code.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
      return nil
    }
    return code
  }
}
