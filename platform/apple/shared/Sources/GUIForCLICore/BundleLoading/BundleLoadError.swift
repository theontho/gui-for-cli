import Foundation

public enum BundleLoadError: LocalizedError, Equatable {
  case sourceNotFound(URL)
  case unsupportedFormat(URL)
  case manifestNotFound(URL)
  case multipleManifests(URL)
  case pageFileNotFound(URL)
  case invalidPagePath(String)
  case archiveExtractionFailed(URL, String)
  case unmanagedWorkspace(URL)

  public var errorDescription: String? {
    switch self {
    case .sourceNotFound(let url):
      "Bundle source does not exist: \(url.path)"
    case .unsupportedFormat(let url):
      "Unsupported bundle format: \(url.lastPathComponent)"
    case .manifestNotFound(let url):
      "No manifest.json found in bundle source: \(url.path)"
    case .multipleManifests(let url):
      "Multiple manifest.json files found near bundle root: \(url.path)"
    case .pageFileNotFound(let url):
      "Bundle page file does not exist: \(url.path)"
    case .invalidPagePath(let path):
      "Bundle page paths must be file names inside pages/: \(path)"
    case .archiveExtractionFailed(let url, let detail):
      "Failed to extract \(url.lastPathComponent): \(detail)"
    case .unmanagedWorkspace(let url):
      "Refusing to use non-empty unmanaged workspace: \(url.path)"
    }
  }
}
