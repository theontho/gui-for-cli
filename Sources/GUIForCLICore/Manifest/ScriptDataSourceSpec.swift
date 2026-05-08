import Foundation

public struct ScriptDataSourceSpec: Codable, Equatable, Sendable {
  public var path: String
  public var arguments: [String]
  public var environment: [String: String]
  public var workingDirectory: String?

  public init(
    path: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    workingDirectory: String? = nil
  ) {
    self.path = path
    self.arguments = arguments
    self.environment = environment
    self.workingDirectory = workingDirectory
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try container.decode(String.self, forKey: .path)
    arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
    environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
    workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
  }
}
