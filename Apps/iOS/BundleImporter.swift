import Foundation

import GUIForCLICore

/// Copies a bundle URL (folder or manifest.json) selected via the file picker
/// into the app's sandboxed Imports directory, then returns the destination URL.
enum BundleImporter {
  static func copyToSandbox(from url: URL) throws -> URL {
    let importsDir = try importsDirectory()
    let bundleName = url.deletingPathExtension().lastPathComponent
    let destination = importsDir.appendingPathComponent(bundleName, isDirectory: true)

    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }

    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

    if isDir.boolValue {
      // Folder bundle: copy directory directly.
      try FileManager.default.copyItem(at: url, to: destination)
    } else if url.pathExtension.lowercased() == "json" {
      // manifest.json: treat its parent directory as the bundle root.
      let parentURL = url.deletingLastPathComponent()
      try FileManager.default.copyItem(at: parentURL, to: destination)
    } else {
      throw BundleImportError.unsupportedFileType(url.lastPathComponent)
    }

    return destination
  }

  private static func importsDirectory() throws -> URL {
    let base = AppPaths.defaultDataDirectory().appendingPathComponent("Imports", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
  }
}

enum BundleImportError: LocalizedError {
  case unsupportedFileType(String)

  var errorDescription: String? {
    switch self {
    case .unsupportedFileType(let name):
      "Cannot import \"\(name)\". Select a bundle folder or a manifest.json file."
    }
  }
}
