import Foundation

public struct ConfigFileSpec: Codable, Equatable, Sendable {
  public var path: String
  public var format: ConfigFileFormat
  public var bootstrap: ConfigBootstrapSpec?

  public init(
    path: String,
    format: ConfigFileFormat = .toml,
    bootstrap: ConfigBootstrapSpec? = nil
  ) {
    self.path = path
    self.format = format
    self.bootstrap = bootstrap
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try container.decode(String.self, forKey: .path)
    format = try container.decodeIfPresent(ConfigFileFormat.self, forKey: .format) ?? .toml
    bootstrap = try container.decodeIfPresent(ConfigBootstrapSpec.self, forKey: .bootstrap)
  }
}

public enum ConfigFileFormat: String, Codable, Equatable, Sendable {
  case toml
}
