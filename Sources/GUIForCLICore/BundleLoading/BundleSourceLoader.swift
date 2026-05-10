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

    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    let fingerprint = try bundleFingerprint(at: sourceURL, preserving: preservedNames)
    let stampURL = destinationURL.appendingPathComponent(
      ".gui-for-cli-source-stamp", isDirectory: false)
    if fileManager.fileExists(atPath: destinationURL.appendingPathComponent("manifest.json").path),
      (try? String(contentsOf: stampURL, encoding: .utf8)) == fingerprint
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
    try fingerprint.write(to: stampURL, atomically: true, encoding: .utf8)
  }

  private func bundleFingerprint(at rootURL: URL, preserving preservedNames: Set<String>) throws
    -> String
  {
    guard
      let enumerator = fileManager.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return ""
    }

    var parts: [String] = []
    for case let fileURL as URL in enumerator {
      let relativePath = String(fileURL.path.dropFirst(rootURL.path.count + 1))
      guard let firstComponent = relativePath.split(separator: "/", maxSplits: 1).first,
        !preservedNames.contains(String(firstComponent))
      else {
        enumerator.skipDescendants()
        continue
      }
      let values = try fileURL.resourceValues(forKeys: [
        .isRegularFileKey, .contentModificationDateKey, .fileSizeKey,
      ])
      guard values.isRegularFile == true else { continue }
      let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
      let size = values.fileSize ?? 0
      parts.append("\(relativePath)\t\(size)\t\(modified)")
    }
    return parts.sorted().joined(separator: "\n")
  }

  private func markDemoScriptsExecutable(in rootURL: URL) throws {
    let scriptsURL = rootURL.appendingPathComponent("scripts", isDirectory: true)
    for scriptName in [
      "setup-wgsextract-pixi.sh", "bootstrap-wgsextract-config.sh", "run-wgsextract.sh",
      "list-reference-genomes.py", "delete-reference-genome.sh",
    ] {
      let scriptURL = scriptsURL.appendingPathComponent(scriptName, isDirectory: false)
      if fileManager.fileExists(atPath: scriptURL.path) {
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
      }
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
}

enum SourceKind: Equatable {
  case directory
  case manifestFile
  case archive(BundleArchiveFormat)
}
