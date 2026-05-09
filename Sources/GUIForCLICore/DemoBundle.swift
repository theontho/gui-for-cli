import Foundation

public enum DemoBundle {
  /// Returns the root URL of the bundled WGS Extract demo bundle, or `nil` if
  /// the resource cannot be located (e.g. on iOS production builds where the
  /// symlink was not materialised at build time).
  public static var wgsExtractResourceRootURLIfAvailable: URL? {
    if let url = Bundle.module.url(
      forResource: "WGSExtract", withExtension: nil, subdirectory: "Resources/DemoBundles")
    {
      if containsManifest(url) {
        return url
      }
      let resolvedURL = url.resolvingSymlinksInPath()
      if containsManifest(resolvedURL) {
        return resolvedURL
      }
    }

    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Examples/WGSExtract", isDirectory: true)
    if containsManifest(sourceURL) {
      return sourceURL
    }

    return nil
  }

  /// Returns the root URL of the bundled WGS Extract demo bundle.
  ///
  /// - Important: Crashes with `preconditionFailure` if the bundle resources
  ///   are missing. Prefer ``wgsExtractResourceRootURLIfAvailable`` on iOS
  ///   where the symlink may not be materialised in production builds.
  public static var wgsExtractResourceRootURL: URL {
    guard let url = wgsExtractResourceRootURLIfAvailable else {
      preconditionFailure("Missing bundled WGS Extract resources.")
    }
    return url
  }

  public static var wgsExtractIconURL: URL {
    wgsExtractResourceRootURL.appendingPathComponent("Assets/icon.png", isDirectory: false)
  }

  /// Returns the WGS Extract demo manifest, or `nil` if the bundle resources
  /// are not available on this platform/build.
  public static var wgsExtractIfAvailable: CLIBundleManifest? {
    guard let url = wgsExtractResourceRootURLIfAvailable else { return nil }
    return try? BundleSourceLoader().load(from: url).manifest
  }

  public static let wgsExtract: CLIBundleManifest = {
    do {
      return try BundleSourceLoader().load(from: wgsExtractResourceRootURL).manifest
    } catch {
      preconditionFailure("Invalid bundled WGS Extract manifest: \(error.localizedDescription)")
    }
  }()

  /// A minimal placeholder manifest used on iOS when no bundle has been loaded.
  public static let placeholder: CLIBundleManifest = CLIBundleManifest(
    id: "gui-for-cli-placeholder",
    displayName: "No Bundle Loaded",
    summary: "Open or import a bundle to get started.",
    iconName: "folder",
    pages: [
      BundlePage(
        id: "home",
        title: "No Bundle Loaded",
        summary: "Open or import a bundle to get started.",
        iconName: "folder.badge.questionmark",
        sections: []
      )
    ]
  )

  private static func containsManifest(_ url: URL) -> Bool {
    FileManager.default.fileExists(
      atPath: url.appendingPathComponent("manifest.json", isDirectory: false).path)
  }
}
