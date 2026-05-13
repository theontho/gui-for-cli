import Foundation

extension BundleSourceLoader {
  func loadManifest(
    in rootURL: URL,
    isTemporary: Bool,
    localizationCode: String?
  ) throws -> LoadedBundle {
    let manifestURL = try findManifest(in: rootURL)
    return try loadManifest(
      at: manifestURL, rootURL: manifestURL.deletingLastPathComponent(), isTemporary: isTemporary,
      localizationCode: localizationCode)
  }

  func loadManifest(
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
    let iconMap = try loadIconMap(rootURL: rootURL)
    return LoadedBundle(
      manifest: manifest,
      manifestURL: manifestURL,
      rootURL: rootURL,
      isTemporary: isTemporary,
      localizationCode: localizationCode,
      localizationOptions: localizationOptions,
      localizationLabels: BundleLocalizationLabels(table: stringTable),
      iconMap: iconMap
    )
  }

  func findManifest(in rootURL: URL) throws -> URL {
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

  func loadPageFiles(_ pageFiles: [String], rootURL: URL) throws -> [BundlePage] {
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

  func isSafePageFileName(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty
      && !trimmed.hasPrefix("/")
      && !trimmed.contains("/")
      && !trimmed.split(separator: "/").contains("..")
      && trimmed.hasSuffix(".json")
  }
}
