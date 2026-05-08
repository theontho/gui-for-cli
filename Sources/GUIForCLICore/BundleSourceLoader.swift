import Foundation

public struct LoadedBundle: Equatable, Sendable {
  public var manifest: CLIBundleManifest
  public var manifestURL: URL
  public var rootURL: URL
  public var isTemporary: Bool
  public var localizationCode: String
  public var localizationOptions: [BundleLocalizationOption]
  public var localizationLabels: BundleLocalizationLabels

  public init(
    manifest: CLIBundleManifest,
    manifestURL: URL,
    rootURL: URL,
    isTemporary: Bool,
    localizationCode: String = BundleSourceLoader.defaultLocalizationCode,
    localizationOptions: [BundleLocalizationOption] = [],
    localizationLabels: BundleLocalizationLabels = BundleLocalizationLabels()
  ) {
    self.manifest = manifest
    self.manifestURL = manifestURL
    self.rootURL = rootURL
    self.isTemporary = isTemporary
    self.localizationCode = localizationCode
    self.localizationOptions = localizationOptions
    self.localizationLabels = localizationLabels
  }
}

public enum BundleLoadError: LocalizedError, Equatable {
  case sourceNotFound(URL)
  case unsupportedFormat(URL)
  case manifestNotFound(URL)
  case multipleManifests(URL)
  case pageFileNotFound(URL)
  case invalidPagePath(String)
  case archiveExtractionFailed(URL, String)

  public var errorDescription: String? {
    switch self {
    case .sourceNotFound(let url):
      "Bundle source does not exist: \(url.path)"
    case .unsupportedFormat(let url):
      "Unsupported bundle format: \(url.lastPathComponent)"
    case .manifestNotFound(let url):
      "No manifest.json found in bundle source: \(url.path)"
    case .multipleManifests(let url):
      "Multiple manifest.json files found near bundle root: \(url.path)"
    case .pageFileNotFound(let url):
      "Bundle page file does not exist: \(url.path)"
    case .invalidPagePath(let path):
      "Bundle page paths must be file names inside pages/: \(path)"
    case .archiveExtractionFailed(let url, let detail):
      "Failed to extract \(url.lastPathComponent): \(detail)"
    }
  }
}

public enum BundleArchiveFormat: Equatable, Sendable {
  case zip
  case tar
  case gzipManifest
}

public protocol BundleArchiveExtracting {
  func extractArchive(
    at sourceURL: URL,
    format: BundleArchiveFormat,
    to destinationURL: URL
  ) throws
}

public struct SystemBundleArchiveExtractor: BundleArchiveExtracting {
  public init() {}

  public func extractArchive(
    at sourceURL: URL,
    format: BundleArchiveFormat,
    to destinationURL: URL
  ) throws {
    #if os(macOS)
      try FileManager.default.createDirectory(
        at: destinationURL, withIntermediateDirectories: true)
      switch format {
      case .zip:
        try run("/usr/bin/ditto", ["-x", "-k", sourceURL.path, destinationURL.path], sourceURL)
      case .tar:
        try run("/usr/bin/tar", ["-xf", sourceURL.path, "-C", destinationURL.path], sourceURL)
      case .gzipManifest:
        let manifestURL = destinationURL.appendingPathComponent("manifest.json", isDirectory: false)
        try gunzip(sourceURL, to: manifestURL)
      }
    #else
      throw BundleLoadError.unsupportedFormat(sourceURL)
    #endif
  }

  #if os(macOS)
    private func run(_ executable: String, _ arguments: [String], _ sourceURL: URL) throws {
      let process = Process()
      let output = Pipe()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.standardOutput = output
      process.standardError = output
      try process.run()
      process.waitUntilExit()

      let data = output.fileHandleForReading.readDataToEndOfFile()
      let text = String(data: data, encoding: .utf8) ?? ""
      guard process.terminationStatus == 0 else {
        throw BundleLoadError.archiveExtractionFailed(sourceURL, text)
      }
    }

    private func gunzip(_ sourceURL: URL, to destinationURL: URL) throws {
      FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
      let outputHandle = try FileHandle(forWritingTo: destinationURL)
      defer { try? outputHandle.close() }

      let process = Process()
      let error = Pipe()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
      process.arguments = ["-c", sourceURL.path]
      process.standardOutput = outputHandle
      process.standardError = error
      try process.run()
      process.waitUntilExit()

      let data = error.fileHandleForReading.readDataToEndOfFile()
      let text = String(data: data, encoding: .utf8) ?? ""
      guard process.terminationStatus == 0 else {
        throw BundleLoadError.archiveExtractionFailed(sourceURL, text)
      }
    }
  #endif
}

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
    let localizationOptions = try loadLocalizationOptions(rootURL: rootURL)
    let localizationCode = resolvedLocalizationCode(
      requestedLocalizationCode,
      options: localizationOptions)
    let stringTable = try loadStringTable(rootURL: rootURL, localizationCode: localizationCode)
    if let stringTable {
      manifest = try BundleLocalizationResolver(table: stringTable).localized(manifest)
      try manifest.validate()
    }
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

  private func loadStringTable(rootURL: URL, localizationCode: String) throws -> BundleStringTable?
  {
    guard let stringsURL = baseStringsURL(rootURL: rootURL) else { return nil }
    let baseTable = try BundleStringTable(tomlData: Data(contentsOf: stringsURL))
    guard localizationCode != Self.defaultLocalizationCode,
      let localizedURL = localizedStringsURL(rootURL: rootURL, code: localizationCode),
      fileManager.fileExists(atPath: localizedURL.path)
    else {
      return baseTable
    }
    let localizedTable = try BundleStringTable(tomlData: Data(contentsOf: localizedURL))
    return baseTable.merging(localizedTable)
  }

  private func loadLocalizationOptions(rootURL: URL) throws -> [BundleLocalizationOption] {
    guard let baseURL = baseStringsURL(rootURL: rootURL) else { return [] }

    let baseTable = try BundleStringTable(tomlData: Data(contentsOf: baseURL))
    var options = [
      BundleLocalizationOption(
        code: baseTable["language.code"] ?? Self.defaultLocalizationCode,
        displayName: baseTable["language.name"] ?? "English")
    ]

    let stringsDirectory = baseURL.deletingLastPathComponent()
    let children = try fileManager.contentsOfDirectory(
      at: stringsDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles])
    for url in children {
      guard let code = localizationCode(forStringsFileName: url.lastPathComponent),
        code != Self.defaultLocalizationCode
      else {
        continue
      }
      let table = try BundleStringTable(tomlData: Data(contentsOf: url))
      options.append(
        BundleLocalizationOption(
          code: table["language.code"] ?? code,
          displayName: table["language.name"] ?? code))
    }

    return options.sorted { first, second in
      if first.code == Self.defaultLocalizationCode { return true }
      if second.code == Self.defaultLocalizationCode { return false }
      return first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
    }
  }

  private func resolvedLocalizationCode(
    _ requestedLocalizationCode: String?,
    options: [BundleLocalizationOption]
  ) -> String {
    let requested = requestedLocalizationCode?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let requested, !requested.isEmpty else {
      return Self.defaultLocalizationCode
    }
    guard options.contains(where: { $0.code == requested }) else {
      return Self.defaultLocalizationCode
    }
    return requested
  }

  /// Returns the URL of the base (English) `strings.toml` inside the bundle's
  /// `strings/` subfolder.
  private func baseStringsURL(rootURL: URL) -> URL? {
    let url = rootURL.appendingPathComponent("strings", isDirectory: true)
      .appendingPathComponent("strings.toml", isDirectory: false)
    return fileManager.fileExists(atPath: url.path) ? url : nil
  }

  private func localizedStringsURL(rootURL: URL, code: String) -> URL? {
    guard code.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
      return nil
    }
    return rootURL.appendingPathComponent("strings", isDirectory: true)
      .appendingPathComponent("strings.\(code).toml", isDirectory: false)
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
