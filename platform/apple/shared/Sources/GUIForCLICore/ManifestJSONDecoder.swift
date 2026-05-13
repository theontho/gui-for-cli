import Foundation

public struct ManifestJSONDecoder: Sendable {
  public init() {}

  public func decode(_ type: CLIBundleManifest.Type, from data: Data) throws -> CLIBundleManifest {
    let decoder = JSONDecoder()
    let manifest = try decoder.decode(CLIBundleManifest.self, from: data)
    try manifest.validate()
    return manifest
  }
}
