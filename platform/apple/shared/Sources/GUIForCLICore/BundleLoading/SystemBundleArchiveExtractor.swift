import Foundation

public struct SystemBundleArchiveExtractor: BundleArchiveExtracting {
  public init() {}

  public func extractArchive(
    at sourceURL: URL,
    format: BundleArchiveFormat,
    to destinationURL: URL
  ) throws {
    #if os(macOS)
      try FileManager.default.createDirectory(
        at: destinationURL, withIntermediateDirectories: true)
      switch format {
      case .zip:
        try run("/usr/bin/ditto", ["-x", "-k", sourceURL.path, destinationURL.path], sourceURL)
      case .tar:
        try run("/usr/bin/tar", ["-xf", sourceURL.path, "-C", destinationURL.path], sourceURL)
      case .gzipManifest:
        let manifestURL = destinationURL.appendingPathComponent("manifest.json", isDirectory: false)
        try gunzip(sourceURL, to: manifestURL)
      }
    #else
      throw BundleLoadError.unsupportedFormat(sourceURL)
    #endif
  }

  #if os(macOS)
    private func run(_ executable: String, _ arguments: [String], _ sourceURL: URL) throws {
      let process = Process()
      let output = Pipe()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.standardOutput = output
      process.standardError = output
      try process.run()
      let data = output.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      let text = String(data: data, encoding: .utf8) ?? ""
      guard process.terminationStatus == 0 else {
        throw BundleLoadError.archiveExtractionFailed(sourceURL, text)
      }
    }

    private func gunzip(_ sourceURL: URL, to destinationURL: URL) throws {
      FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
      let outputHandle = try FileHandle(forWritingTo: destinationURL)
      defer { try? outputHandle.close() }

      let process = Process()
      let error = Pipe()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
      process.arguments = ["-c", sourceURL.path]
      process.standardOutput = outputHandle
      process.standardError = error
      try process.run()
      let data = error.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      let text = String(data: data, encoding: .utf8) ?? ""
      guard process.terminationStatus == 0 else {
        throw BundleLoadError.archiveExtractionFailed(sourceURL, text)
      }
    }
  #endif
}
