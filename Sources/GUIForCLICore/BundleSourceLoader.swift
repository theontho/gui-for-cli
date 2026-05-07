import Foundation

public struct LoadedBundle: Equatable, Sendable {
  public var manifest: CLIBundleManifest
  public var manifestURL: URL
  public var rootURL: URL
  public var isTemporary: Bool

  public init(
    manifest: CLIBundleManifest,
    manifestURL: URL,
    rootURL: URL,
    isTemporary: Bool
  ) {
    self.manifest = manifest
    self.manifestURL = manifestURL
    self.rootURL = rootURL
    self.isTemporary = isTemporary
  }
}

public enum BundleLoadError: LocalizedError, Equatable {
  case sourceNotFound(URL)
  case unsupportedFormat(URL)
  case manifestNotFound(URL)
  case multipleManifests(URL)
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

  public func load(from sourceURL: URL) throws -> LoadedBundle {
    guard fileManager.fileExists(atPath: sourceURL.path) else {
      throw BundleLoadError.sourceNotFound(sourceURL)
    }

    switch try sourceKind(for: sourceURL) {
    case .directory:
      return try loadManifest(in: sourceURL, isTemporary: false)
    case .manifestFile:
      return try loadManifest(
        at: sourceURL, rootURL: sourceURL.deletingLastPathComponent(), isTemporary: false)
    case .archive(let format):
      let destination = temporaryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
      try archiveExtractor.extractArchive(at: sourceURL, format: format, to: destination)
      return try loadManifest(in: destination, isTemporary: true)
    }
  }

  public func writeDemoBundle(to destinationURL: URL, overwrite: Bool = false) throws {
    if fileManager.fileExists(atPath: destinationURL.path) {
      if overwrite {
        try fileManager.removeItem(at: destinationURL)
      } else {
        throw ConfigError.fileExists(destinationURL)
      }
    }
    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    let manifestURL = destinationURL.appendingPathComponent("manifest.json", isDirectory: false)
    try DemoBundleManifest.json.write(to: manifestURL, atomically: true, encoding: .utf8)
    let stringsURL = destinationURL.appendingPathComponent("strings.toml", isDirectory: false)
    try DemoBundleManifest.stringsToml.write(to: stringsURL, atomically: true, encoding: .utf8)
    let assetsURL = destinationURL.appendingPathComponent("Assets", isDirectory: true)
    try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
    try fileManager.copyItem(
      at: DemoBundle.wgsExtractIconURL,
      to: assetsURL.appendingPathComponent("icon.png", isDirectory: false))
    let scriptsURL = destinationURL.appendingPathComponent("scripts", isDirectory: true)
    try fileManager.createDirectory(at: scriptsURL, withIntermediateDirectories: true)
    let setupURL = scriptsURL.appendingPathComponent(
      "setup-wgsextract-pixi.sh", isDirectory: false)
    try DemoBundleManifest.wgsExtractPixiSetupScript.write(
      to: setupURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: setupURL.path)
    let bootstrapURL = scriptsURL.appendingPathComponent(
      "bootstrap-wgsextract-config.sh", isDirectory: false)
    try DemoBundleManifest.wgsExtractConfigBootstrapScript.write(
      to: bootstrapURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bootstrapURL.path)
  }

  private func loadManifest(in rootURL: URL, isTemporary: Bool) throws -> LoadedBundle {
    let manifestURL = try findManifest(in: rootURL)
    return try loadManifest(
      at: manifestURL, rootURL: manifestURL.deletingLastPathComponent(), isTemporary: isTemporary)
  }

  private func loadManifest(at manifestURL: URL, rootURL: URL, isTemporary: Bool) throws
    -> LoadedBundle
  {
    let data = try Data(contentsOf: manifestURL)
    var manifest = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: data)
    if let stringTable = try loadStringTable(rootURL: rootURL) {
      manifest = try BundleLocalizationResolver(table: stringTable).localized(manifest)
      try manifest.validate()
    }
    return LoadedBundle(
      manifest: manifest,
      manifestURL: manifestURL,
      rootURL: rootURL,
      isTemporary: isTemporary
    )
  }

  private func loadStringTable(rootURL: URL) throws -> BundleStringTable? {
    let stringsURL = rootURL.appendingPathComponent("strings.toml", isDirectory: false)
    guard fileManager.fileExists(atPath: stringsURL.path) else { return nil }
    return try BundleStringTable(tomlData: Data(contentsOf: stringsURL))
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
