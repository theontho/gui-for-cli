import Foundation

public enum DemoBundle {
  public static var defaultResourceRootURL: URL {
    embeddedResourceRootURL ?? wgsExtractResourceRootURL
  }

  public static let defaultManifest: CLIBundleManifest = {
    do {
      return try BundleSourceLoader().load(from: defaultResourceRootURL).manifest
    } catch {
      preconditionFailure("Invalid bundled default manifest: \(error.localizedDescription)")
    }
  }()

  public static var wgsExtractResourceRootURL: URL {
    if let url = resourceRootURL(named: "WGSExtract") {
      return url
    }

    var sourceRootURL = URL(fileURLWithPath: #filePath)
    for _ in 0..<8 {
      sourceRootURL.deleteLastPathComponent()
      let sourceURL = sourceRootURL.appendingPathComponent("examples/WGSExtract", isDirectory: true)
      if containsManifest(sourceURL) {
        return sourceURL
      }
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

  private static var embeddedResourceRootURL: URL? {
    resourceRootURL(named: "EmbeddedBundle")
  }

  private static func resourceRootURL(named name: String) -> URL? {
    guard
      let url = Bundle.module.url(
        forResource: name, withExtension: nil, subdirectory: "Resources/DemoBundles")
    else {
      return nil
    }
    if containsManifest(url) {
      return url
    }
    let resolvedURL = url.resolvingSymlinksInPath()
    if containsManifest(resolvedURL) {
      return resolvedURL
    }
    return nil
  }

  private static func containsManifest(_ url: URL) -> Bool {
    FileManager.default.fileExists(
      atPath: url.appendingPathComponent("manifest.json", isDirectory: false).path)
  }
}
