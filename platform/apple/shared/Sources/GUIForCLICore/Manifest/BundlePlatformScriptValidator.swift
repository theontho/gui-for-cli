import Foundation

enum BundlePlatformScriptValidator {
  static func validate(
    manifest: CLIBundleManifest,
    rootURL: URL,
    fileManager: FileManager = .default
  ) throws {
    guard !referencedScriptStems(in: manifest).isEmpty else { return }

    let scriptsURL = rootURL.appendingPathComponent("scripts", isDirectory: true)
    let folders = try platformScriptFolders(in: scriptsURL, fileManager: fileManager)
    guard !folders.isEmpty else { return }
    let shared = try scriptStems(in: scriptsURL, fileManager: fileManager)
    for folderURL in folders {
      let required = referencedScriptStems(
        in: manifest,
        platform: platform(for: folderURL, scriptsURL: scriptsURL))
      guard !required.isEmpty else { continue }
      let present = shared.union(try scriptStems(in: folderURL, fileManager: fileManager))
      let missing = required.subtracting(present).sorted()
      if !missing.isEmpty {
        throw BundleValidationError.missingPlatformScripts(
          folder: relativePath(for: folderURL, under: rootURL),
          scripts: missing)
      }
    }
  }

  private static func scriptStems(in url: URL, fileManager: FileManager) throws -> Set<String> {
    let files = try fileManager.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )
    return Set(
      files
        .filter {
          ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) == false
        }
        .map { stem($0.lastPathComponent) }
    )
  }

  private static func referencedScriptStems(
    in manifest: CLIBundleManifest,
    platform: SetupPlatform? = nil
  ) -> Set<String> {
    var values: [String] = []
    values.append(
      contentsOf: manifest.setup.steps.compactMap { step in
        isRequiredScriptStep(step, platform: platform) ? step.value : nil
      })
    values.append(
      contentsOf: manifest.uninstall.steps.compactMap { step in
        isRequiredScriptStep(step, platform: platform) ? step.value : nil
      })
    for page in manifest.pages {
      for section in page.sections {
        if let dataSource = section.dataSource { values.append(dataSource.path) }
        values.append(contentsOf: section.actions.map(\.command.executable))
        for control in section.controls {
          if let dataSource = control.dataSource { values.append(dataSource.path) }
          values.append(contentsOf: control.rowActions.map(\.command.executable))
        }
      }
    }
    return Set(
      values.compactMap { value in
        guard isScriptPath(value) else { return nil }
        return stem(normalize(value).split(separator: "/").last.map(String.init) ?? "")
      })
  }

  private static func platformScriptFolders(in scriptsURL: URL, fileManager: FileManager) throws
    -> [URL]
  {
    var folders: [URL] = []
    for name in ["windows", "posix", "macos"] {
      let folder = scriptsURL.appendingPathComponent(name, isDirectory: true)
      if directoryExists(folder, fileManager: fileManager) { folders.append(folder) }
    }

    let linuxURL = scriptsURL.appendingPathComponent("linux", isDirectory: true)
    if directoryExists(linuxURL, fileManager: fileManager) {
      let entries = try fileManager.contentsOfDirectory(
        at: linuxURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
      if entries.contains(where: {
        ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) == false
      }) {
        folders.append(linuxURL)
      }
      folders.append(
        contentsOf: entries.filter {
          ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) == true
        })
    }
    return folders
  }

  private static func isScriptPath(_ value: String) -> Bool {
    let normalized = normalize(value)
    return normalized.hasPrefix("scripts/")
      && !normalized.split(separator: "/").contains("..")
      && !(normalized as NSString).isAbsolutePath
  }

  private static func isRequiredScriptStep(_ step: SetupStep, platform: SetupPlatform?) -> Bool {
    guard step.kind == .setupScript || step.kind == .bundledScript else { return false }
    guard let platform else { return true }
    return step.applies(to: platform)
  }

  private static func normalize(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "/")
      .replacingOccurrences(of: #"^\{\{bundleRoot\}\}/"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"^\./"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"^/"#, with: "", options: .regularExpression)
  }

  private static func stem(_ fileName: String) -> String {
    (fileName as NSString).deletingPathExtension
  }

  private static func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private static func relativePath(for url: URL, under rootURL: URL) -> String {
    let rootPath = rootURL.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(rootPath + "/") else { return path }
    return String(path.dropFirst(rootPath.count + 1))
  }

  private static func platform(for folderURL: URL, scriptsURL: URL) -> SetupPlatform {
    let scriptsPath = scriptsURL.standardizedFileURL.path
    let folderPath = folderURL.standardizedFileURL.path
    let relative =
      folderPath.hasPrefix(scriptsPath + "/")
      ? String(folderPath.dropFirst(scriptsPath.count + 1))
      : folderURL.lastPathComponent
    if relative == "windows" { return .windows }
    if relative == "macos" { return .macos }
    if relative == "posix" { return .posix }
    return relative == "linux" || relative.hasPrefix("linux/") ? .linux : .posix
  }
}
