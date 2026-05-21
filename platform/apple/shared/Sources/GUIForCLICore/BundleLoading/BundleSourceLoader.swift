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

    let metadata = try BundleWorkspaceMetadata(
      sourceSignature: sourceSignature(for: sourceURL, preserving: preservedNames))
    let metadataURL = destinationURL.appendingPathComponent(
      BundleWorkspaceMetadata.fileName, isDirectory: false)
    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    if workspaceIsCurrent(
      at: destinationURL,
      metadataURL: metadataURL,
      metadata: metadata)
    {
      return
    }

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
    try writeWorkspaceMetadata(metadata, to: metadataURL)
  }

  private func markDemoScriptsExecutable(in rootURL: URL) throws {
    let scriptsURL = rootURL.appendingPathComponent("scripts", isDirectory: true)
    guard
      let enumerator = fileManager.enumerator(
        at: scriptsURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles])
    else {
      return
    }
    for case let scriptURL as URL in enumerator {
      if ((try? scriptURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) == true
      {
        continue
      }
      try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }
  }

  func sourceKind(for sourceURL: URL) throws -> SourceKind {
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

  private func sourceSignature(for sourceURL: URL, preserving preservedNames: Set<String>) throws
    -> [String]
  {
    guard
      let enumerator = fileManager.enumerator(
        at: sourceURL,
        includingPropertiesForKeys: [
          .isDirectoryKey, .contentModificationDateKey, .fileSizeKey,
        ],
        options: [.skipsHiddenFiles])
    else {
      return []
    }

    let sourcePath = sourceURL.standardizedFileURL.path
    var entries: [String] = []
    for case let url as URL in enumerator {
      let relativePath = relativePath(for: url, under: sourcePath)
      guard !relativePath.isEmpty else { continue }
      if let rootName = relativePath.split(separator: "/", maxSplits: 1).first,
        preservedNames.contains(String(rootName))
      {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
          enumerator.skipDescendants()
        }
        continue
      }

      let values = try url.resourceValues(forKeys: [
        .isDirectoryKey, .contentModificationDateKey, .fileSizeKey,
      ])
      let kind = values.isDirectory == true ? "d" : "f"
      let size = values.fileSize ?? 0
      let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
      entries.append("\(relativePath)|\(kind)|\(size)|\(modified)")
    }
    return entries.sorted()
  }

  private func relativePath(for url: URL, under sourcePath: String) -> String {
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(sourcePath + "/") else { return "" }
    return String(path.dropFirst(sourcePath.count + 1))
  }

  private func workspaceIsCurrent(
    at destinationURL: URL,
    metadataURL: URL,
    metadata: BundleWorkspaceMetadata
  ) -> Bool {
    guard
      let data = try? Data(contentsOf: metadataURL),
      let stored = try? JSONDecoder().decode(BundleWorkspaceMetadata.self, from: data),
      stored == metadata
    else {
      return false
    }
    return metadata.sourceSignature.allSatisfy { entry in
      guard let relativePath = entry.split(separator: "|", maxSplits: 1).first else {
        return false
      }
      return fileManager.fileExists(
        atPath: destinationURL.appendingPathComponent(String(relativePath)).path)
    }
  }

  private func writeWorkspaceMetadata(_ metadata: BundleWorkspaceMetadata, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(metadata)
    try data.write(to: url, options: .atomic)
  }
}

enum SourceKind: Equatable {
  case directory
  case manifestFile
  case archive(BundleArchiveFormat)
}

private struct BundleWorkspaceMetadata: Codable, Equatable {
  static let fileName = ".gui-for-cli-workspace.json"
  private static let currentVersion = 1

  var version: Int
  var sourceSignature: [String]

  init(sourceSignature: [String]) {
    self.version = Self.currentVersion
    self.sourceSignature = sourceSignature
  }
}
