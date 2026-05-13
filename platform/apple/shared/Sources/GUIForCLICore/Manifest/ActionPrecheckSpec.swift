import Foundation

public struct ActionPrecheckSpec: Codable, Equatable, Sendable {
  /// Required free space at `diskSpacePath`, expressed as gigabytes. The
  /// value is interpolated as a placeholder expression and then evaluated as
  /// a numeric expression (e.g. `"{{bam_path.fileSizeGB}} * 6"`).
  public var diskSpaceGB: String?
  /// Path whose containing volume is checked for free space. Defaults to
  /// `{{out_dir}}` if present, falling back to `{{bundleWorkspace}}`.
  public var diskSpacePath: String?
  /// Optional warning message override (interpolated). Defaults to a
  /// generic "Need X GB free, only Y GB available" message synthesised by
  /// the renderer using the labels table.
  public var warningMessage: String?

  public init(
    diskSpaceGB: String? = nil,
    diskSpacePath: String? = nil,
    warningMessage: String? = nil
  ) {
    self.diskSpaceGB = diskSpaceGB
    self.diskSpacePath = diskSpacePath
    self.warningMessage = warningMessage
  }
}
