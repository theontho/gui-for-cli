import Foundation

public enum DemoBundle {
  public static var wgsExtractResourceRootURL: URL {
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

    preconditionFailure("Missing bundled WGS Extract resources.")
  }

  public static var wgsExtractIconURL: URL {
    wgsExtractResourceRootURL.appendingPathComponent("Assets/icon.png", isDirectory: false)
  }

  public static let wgsExtract: CLIBundleManifest = {
    do {
      return try BundleSourceLoader().load(from: wgsExtractResourceRootURL).manifest
    } catch {
      preconditionFailure("Invalid bundled WGS Extract manifest: \(error.localizedDescription)")
    }
  }()

  private static func containsManifest(_ url: URL) -> Bool {
    FileManager.default.fileExists(
      atPath: url.appendingPathComponent("manifest.json", isDirectory: false).path)
  }
}
