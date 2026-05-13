import Foundation

public struct AppConfigStore: Sendable {
  public let path: URL

  public init(path: URL = AppPaths.configFile()) {
    self.path = path
  }

  public func load() throws -> AppConfig {
    guard FileManager.default.fileExists(atPath: path.path) else {
      return AppConfig()
    }

    let data = try Data(contentsOf: path)
    return try JSONDecoder().decode(AppConfig.self, from: data)
  }

  public func save(_ config: AppConfig) throws {
    try config.validate()
    let directory = path.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(config)
    try data.write(to: path, options: [.atomic])
  }

  public func initializeDefault(force: Bool = false) throws -> AppConfig {
    if FileManager.default.fileExists(atPath: path.path), !force {
      throw ConfigError.fileExists(path)
    }

    let config = AppConfig()
    try save(config)
    return config
  }
}
