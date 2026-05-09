import Foundation
import Testing

@testable import GUIForCLICore

struct CopyingArchiveExtractor: BundleArchiveExtracting {
  func extractArchive(
    at sourceURL: URL,
    format: BundleArchiveFormat,
    to destinationURL: URL
  ) throws {
    try BundleSourceLoader().writeDemoBundle(to: destinationURL, overwrite: true)
  }
}

func temporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("gui-for-cli-tests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

func supportsPOSIXExecutableBitAssertions() -> Bool {
  #if os(Windows)
    false
  #else
    true
  #endif
}
