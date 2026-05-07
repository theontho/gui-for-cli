import Foundation

public enum AppPaths {
  public static let appName = "gui-for-cli"
  public static let appAuthor = "GUI for CLI"
  public static let configDirectoryEnvironmentKey = "GUI_FOR_CLI_CONFIG_DIR"

  public static func configDirectory(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> URL {
    if let override = environment[configDirectoryEnvironmentKey], !override.isEmpty {
      return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
    }

    return applicationSupportDirectory(fileManager: fileManager)
      .appendingPathComponent(appName, isDirectory: true)
  }

  public static func configFile(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> URL {
    configDirectory(environment: environment, fileManager: fileManager)
      .appendingPathComponent("config.json", isDirectory: false)
  }

  public static func defaultDataDirectory(fileManager: FileManager = .default) -> URL {
    applicationSupportDirectory(fileManager: fileManager)
      .appendingPathComponent(appName, isDirectory: true)
      .appendingPathComponent("Data", isDirectory: true)
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
}
