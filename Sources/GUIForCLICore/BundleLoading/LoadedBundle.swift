import Foundation

public struct LoadedBundle: Equatable, Sendable {
  public var manifest: CLIBundleManifest
  public var manifestURL: URL
  public var rootURL: URL
  public var isTemporary: Bool
  public var localizationCode: String
  public var localizationOptions: [BundleLocalizationOption]
  public var localizationLabels: BundleLocalizationLabels

  public init(
    manifest: CLIBundleManifest,
    manifestURL: URL,
    rootURL: URL,
    isTemporary: Bool,
    localizationCode: String = BundleSourceLoader.defaultLocalizationCode,
    localizationOptions: [BundleLocalizationOption] = [],
    localizationLabels: BundleLocalizationLabels = BundleLocalizationLabels()
  ) {
    self.manifest = manifest
    self.manifestURL = manifestURL
    self.rootURL = rootURL
    self.isTemporary = isTemporary
    self.localizationCode = localizationCode
    self.localizationOptions = localizationOptions
    self.localizationLabels = localizationLabels
  }
}
