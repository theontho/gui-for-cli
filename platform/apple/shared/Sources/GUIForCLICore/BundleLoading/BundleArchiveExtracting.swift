import Foundation

public protocol BundleArchiveExtracting {
  func extractArchive(
    at sourceURL: URL,
    format: BundleArchiveFormat,
    to destinationURL: URL
  ) throws
}

public enum BundleArchiveFormat: Equatable, Sendable {
  case zip
  case tar
  case gzipManifest
}
