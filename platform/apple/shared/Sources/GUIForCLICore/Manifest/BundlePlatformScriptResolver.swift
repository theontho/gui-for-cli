import Foundation

enum BundlePlatformScriptResolver {
  static func resolve(_ value: String, rootURL: URL, fileManager: FileManager = .default) -> URL {
    let normalized = normalize(value)
    guard isSafeScriptPath(normalized) else {
      return safeURL(for: normalized, rootURL: rootURL)
    }

    let fileName = (normalized as NSString).lastPathComponent
    let stem = (fileName as NSString).deletingPathExtension
    let extensionName = (fileName as NSString).pathExtension
    let candidateExtensions = extensionName == "py" ? ["py", "sh"] : ["sh", "py"]

    let directories = platformDirectories(for: normalized)
    for directory in directories {
      for candidateExtension in candidateExtensions {
        let candidate =
          rootURL
          .appendingPathComponent(directory, isDirectory: true)
          .appendingPathComponent("\(stem).\(candidateExtension)", isDirectory: false)
        if isInsideRoot(candidate, rootURL: rootURL), fileManager.fileExists(atPath: candidate.path)
        {
          return candidate
        }
      }
    }
    return safeURL(for: normalized, rootURL: rootURL)
  }

  private static func platformDirectories(for normalizedPath: String) -> [String] {
    let directory = (normalizedPath as NSString).deletingLastPathComponent
    #if os(macOS)
      return ["\(directory)/macos", "\(directory)/posix"]
    #elseif os(Linux)
      let distro = linuxDistroID().map { ["\(directory)/linux/\($0)"] } ?? []
      return distro + ["\(directory)/linux", "\(directory)/posix"]
    #else
      return ["\(directory)/posix"]
    #endif
  }

  private static func normalize(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "/")
      .replacingOccurrences(of: #"^\{\{bundleRoot\}\}/"#, with: "", options: .regularExpression)
      .replacingOccurrences(
        of: #"^\{\{bundleWorkspace\}\}/"#, with: "", options: .regularExpression
      )
      .replacingOccurrences(of: #"^\./"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"^/"#, with: "", options: .regularExpression)
  }

  private static func isSafeScriptPath(_ value: String) -> Bool {
    value.hasPrefix("scripts/")
      && !value.split(separator: "/").contains("..")
      && !(value as NSString).isAbsolutePath
  }

  private static func safeURL(for path: String, rootURL: URL) -> URL {
    rootURL.appendingPathComponent(path, isDirectory: false).standardizedFileURL
  }

  private static func isInsideRoot(_ url: URL, rootURL: URL) -> Bool {
    let rootPath = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    return path == rootPath || path.hasPrefix(rootPath + "/")
  }

  #if os(Linux)
    private static func linuxDistroID() -> String? {
      if let override = ProcessInfo.processInfo.environment["GUI_FOR_CLI_LINUX_DISTRO"]?.nonEmpty {
        return sanitizeDistroID(override)
      }
      guard let osRelease = try? String(contentsOfFile: "/etc/os-release", encoding: .utf8) else {
        return nil
      }
      let line = osRelease.split(separator: "\n").first { $0.hasPrefix("ID=") }
      let rawValue = line?.dropFirst(3).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      return rawValue.flatMap { sanitizeDistroID(String($0)) }
    }

    private static func sanitizeDistroID(_ value: String) -> String? {
      let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
      let sanitized = String(
        value
          .lowercased()
          .unicodeScalars
          .map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
          })
      guard sanitized != ".", sanitized != ".." else { return nil }
      return sanitized.nonEmpty
    }
  #endif
}
