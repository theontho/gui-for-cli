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
      let manifest = try ManifestJSONDecoder().decode(
        CLIBundleManifest.self,
        from: Data(DemoBundleManifest.json.utf8)
      )
      let table = try BundleStringTable(tomlData: Data(DemoBundleManifest.stringsToml.utf8))
      return try BundleLocalizationResolver(table: table).localized(manifest)
    } catch {
      preconditionFailure("Invalid bundled WGS Extract manifest: \(error.localizedDescription)")
    }
  }()
}
