import Foundation

public struct BundleSourceLoader {
  public static let defaultLocalizationCode = "en"

  public var fileManager: FileManager
  public var archiveExtractor: BundleArchiveExtracting
  public var temporaryRoot: URL

  public init(
    fileManager: FileManager = .default,
    archiveExtractor: BundleArchiveExtracting = SystemBundleArchiveExtractor(),
    temporaryRoot: URL = FileManager.default.temporaryDirectory
      .appendingPathComponent("gui-for-cli-bundles", isDirectory: true)
  ) {
    self.fileManager = fileManager
    self.archiveExtractor = archiveExtractor
    self.temporaryRoot = temporaryRoot
  }

  public func load(from sourceURL: URL, localizationCode: String? = nil) throws -> LoadedBundle {
    guard fileManager.fileExists(atPath: sourceURL.path) else {
      throw BundleLoadError.sourceNotFound(sourceURL)
    }

    switch try sourceKind(for: sourceURL) {
    case .directory:
      return try loadManifest(
        in: sourceURL, isTemporary: false, localizationCode: localizationCode)
    case .manifestFile:
      return try loadManifest(
        at: sourceURL, rootURL: sourceURL.deletingLastPathComponent(), isTemporary: false,
        localizationCode: localizationCode)
    case .archive(let format):
      let destination = temporaryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
      try archiveExtractor.extractArchive(at: sourceURL, format: format, to: destination)
      return try loadManifest(
        in: destination, isTemporary: true, localizationCode: localizationCode)
    }
  }

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

  public func writeDemoBundle(to destinationURL: URL, overwrite: Bool = false) throws {
    if fileManager.fileExists(atPath: destinationURL.path) {
      if overwrite {
        try fileManager.removeItem(at: destinationURL)
      } else {
        throw ConfigError.fileExists(destinationURL)
      }
    }
    try fileManager.createDirectory(
      at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.copyItem(at: DemoBundle.wgsExtractResourceRootURL, to: destinationURL)
    try markDemoScriptsExecutable(in: destinationURL)
  }

  public func syncBundleWorkspace(
    from sourceURL: URL,
    to destinationURL: URL,
    preserving preservedNames: Set<String> = ["runtime"]
  ) throws {
    guard fileManager.fileExists(atPath: sourceURL.path) else {
      throw BundleLoadError.sourceNotFound(sourceURL)
    }

    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    let children = try fileManager.contentsOfDirectory(
      at: sourceURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )
    for sourceChild in children {
      let destinationChild = destinationURL.appendingPathComponent(
        sourceChild.lastPathComponent,
        isDirectory: (try? sourceChild.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
          == true)
      if preservedNames.contains(sourceChild.lastPathComponent)
        && fileManager.fileExists(atPath: destinationChild.path)
      {
        continue
      }
      if fileManager.fileExists(atPath: destinationChild.path) {
        try fileManager.removeItem(at: destinationChild)
      }
      try fileManager.copyItem(at: sourceChild, to: destinationChild)
    }
    try markDemoScriptsExecutable(in: destinationURL)
  }

  private func loadManifest(
    in rootURL: URL,
    isTemporary: Bool,
    localizationCode: String?
  ) throws -> LoadedBundle {
    let manifestURL = try findManifest(in: rootURL)
    return try loadManifest(
      at: manifestURL, rootURL: manifestURL.deletingLastPathComponent(), isTemporary: isTemporary,
      localizationCode: localizationCode)
  }

  private func loadManifest(
    at manifestURL: URL,
    rootURL: URL,
    isTemporary: Bool,
    localizationCode requestedLocalizationCode: String?
  ) throws -> LoadedBundle {
    let data = try Data(contentsOf: manifestURL)
    var manifest = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: data)
    if manifest.pages.isEmpty, !manifest.pageFiles.isEmpty {
      manifest.pages = try loadPageFiles(manifest.pageFiles, rootURL: rootURL)
      try manifest.validate()
    }
    let localizationOptions = try loadLocalizationOptions(rootURL: rootURL, manifest: manifest)
    let localizationCode = resolvedLocalizationCode(
      requestedLocalizationCode,
      options: localizationOptions,
      defaultCode: manifest.defaultLocalizationCode)
    let stringTable = try loadStringTable(
      rootURL: rootURL,
      manifest: manifest,
      localizationCode: localizationCode)
    manifest = try BundleLocalizationResolver(table: stringTable).localized(manifest)
    try manifest.validate()
    return LoadedBundle(
      manifest: manifest,
      manifestURL: manifestURL,
      rootURL: rootURL,
      isTemporary: isTemporary,
      localizationCode: localizationCode,
      localizationOptions: localizationOptions,
      localizationLabels: BundleLocalizationLabels(table: stringTable)
    )
  }

  private func loadStringTable(
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

  private func loadLocalizationOptions(
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
        let table = try BundleStringTable(tomlData: Data(contentsOf: url))
        let displayName =
          table["language.name"] ?? seen[code]?.displayName ?? code
        seen[code] = BundleLocalizationOption(code: code, displayName: displayName)
      }
    }

    return seen.values.sorted { first, second in
      if first.code == defaultCode { return true }
      if second.code == defaultCode { return false }
      return first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
    }
  }

  private func resolvedLocalizationCode(
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
  private func bundleStringsURL(rootURL: URL, code: String) -> URL? {
    guard code.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
      return nil
    }
    let url = bundleStringsDirectoryURL(rootURL: rootURL)?
      .appendingPathComponent("strings.\(code).toml", isDirectory: false)
    guard let url, fileManager.fileExists(atPath: url.path) else { return nil }
    return url
  }

  private func bundleStringsDirectoryURL(rootURL: URL) -> URL? {
    rootURL.appendingPathComponent("strings", isDirectory: true)
  }

  private func localizationCode(forStringsFileName fileName: String) -> String? {
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

  private func loadPageFiles(_ pageFiles: [String], rootURL: URL) throws -> [BundlePage] {
    let pagesURL = rootURL.appendingPathComponent("pages", isDirectory: true)
    return try pageFiles.map { pageFile in
      guard isSafePageFileName(pageFile) else {
        throw BundleLoadError.invalidPagePath(pageFile)
      }
      let pageURL = pagesURL.appendingPathComponent(pageFile, isDirectory: false)
      guard fileManager.fileExists(atPath: pageURL.path) else {
        throw BundleLoadError.pageFileNotFound(pageURL)
      }
      return try JSONDecoder().decode(BundlePage.self, from: Data(contentsOf: pageURL))
    }
  }

  private func isSafePageFileName(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty
      && !trimmed.hasPrefix("/")
      && !trimmed.contains("/")
      && !trimmed.split(separator: "/").contains("..")
      && trimmed.hasSuffix(".json")
  }

  private func markDemoScriptsExecutable(in rootURL: URL) throws {
    let scriptsURL = rootURL.appendingPathComponent("scripts", isDirectory: true)
    for scriptName in [
      "setup-wgsextract-pixi.sh", "bootstrap-wgsextract-config.sh", "run-wgsextract.sh",
      "list-reference-genomes.sh", "delete-reference-genome.sh",
    ] {
      let scriptURL = scriptsURL.appendingPathComponent(scriptName, isDirectory: false)
      if fileManager.fileExists(atPath: scriptURL.path) {
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
      }
    }
  }

  private func findManifest(in rootURL: URL) throws -> URL {
    let direct = rootURL.appendingPathComponent("manifest.json", isDirectory: false)
    if fileManager.fileExists(atPath: direct.path) {
      return direct
    }

    let children = try fileManager.contentsOfDirectory(
      at: rootURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )
    let manifests = children.compactMap { child -> URL? in
      guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
        return nil
      }
      let manifest = child.appendingPathComponent("manifest.json", isDirectory: false)
      return fileManager.fileExists(atPath: manifest.path) ? manifest : nil
    }

    guard !manifests.isEmpty else {
      throw BundleLoadError.manifestNotFound(rootURL)
    }
    guard manifests.count == 1, let manifest = manifests.first else {
      throw BundleLoadError.multipleManifests(rootURL)
    }
    return manifest
  }

  private func sourceKind(for sourceURL: URL) throws -> SourceKind {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
      throw BundleLoadError.sourceNotFound(sourceURL)
    }
    if isDirectory.boolValue { return .directory }

    let path = sourceURL.path.lowercased()
    if path.hasSuffix(".json") { return .manifestFile }
    if path.hasSuffix(".zip") { return .archive(.zip) }
    if path.hasSuffix(".tar") || path.hasSuffix(".tar.gz") || path.hasSuffix(".tgz")
      || path.hasSuffix(".tar.gzip")
    {
      return .archive(.tar)
    }
    if path.hasSuffix(".gz") || path.hasSuffix(".gzip") { return .archive(.gzipManifest) }
    throw BundleLoadError.unsupportedFormat(sourceURL)
  }
}

private enum SourceKind: Equatable {
  case directory
  case manifestFile
  case archive(BundleArchiveFormat)
}
