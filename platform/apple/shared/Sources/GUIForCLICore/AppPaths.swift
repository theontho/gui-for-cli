import Foundation

public enum AppPaths {
  public static let appName = "gui-for-cli"
  public static let appAuthor = "GUI for CLI"
  public static let configDirectoryEnvironmentKey = "GUI_FOR_CLI_CONFIG_DIR"
  public static let appSupportNameEnvironmentKey = "GUI_FOR_CLI_APP_SUPPORT_NAME"

  public static func configDirectory(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> URL {
    if let override = environment[configDirectoryEnvironmentKey], !override.isEmpty {
      return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
    }

    return appSupportDirectory(environment: environment, fileManager: fileManager)
  }

  public static func configFile(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> URL {
    configDirectory(environment: environment, fileManager: fileManager)
      .appendingPathComponent("config.json", isDirectory: false)
  }

  public static func defaultDataDirectory(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> URL {
    appSupportDirectory(environment: environment, fileManager: fileManager)
      .appendingPathComponent("Data", isDirectory: true)
  }

  public static func bundleWorkspaceDirectory(
    for bundleID: String,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> URL {
    appSupportDirectory(environment: environment, fileManager: fileManager)
      .appendingPathComponent("BundleWorkspaces", isDirectory: true)
      .appendingPathComponent(safePathComponent(bundleID), isDirectory: true)
  }

  public static func appSupportDirectory(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundle: Bundle = .main,
    fileManager: FileManager = .default
  ) -> URL {
    applicationSupportDirectory(fileManager: fileManager)
      .appendingPathComponent(
        appSupportContainerName(environment: environment, bundle: bundle),
        isDirectory: true)
  }

  public static func appSupportContainerName(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundle: Bundle = .main
  ) -> String {
    if let override = environment[appSupportNameEnvironmentKey],
      !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return safePathComponent(override)
    }
    if bundle.bundleURL.pathExtension == "app",
      let identifier = bundle.bundleIdentifier,
      identifier.hasPrefix("dev.guiforcli.")
    {
      return safePathComponent(identifier)
    }
    return appName
  }

  private static func applicationSupportDirectory(fileManager: FileManager) -> URL {
    if let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first
    {
      return directory
    }

    return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)
  }

  private static func safePathComponent(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    let sanitized = String(
      value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    return trimmed.isEmpty ? "bundle" : trimmed
  }
}
