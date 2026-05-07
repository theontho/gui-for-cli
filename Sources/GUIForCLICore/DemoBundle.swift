import Foundation

public enum DemoBundle {
  public static var wgsExtractResourceRootURL: URL {
    guard
      let url = Bundle.module.url(
        forResource: "WGSExtract", withExtension: nil, subdirectory: "Resources/DemoBundles")
    else {
      preconditionFailure("Missing bundled WGS Extract resources.")
    }
    return url
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
}
