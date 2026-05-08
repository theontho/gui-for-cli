import Foundation

public struct ConfigBootstrapSpec: Codable, Equatable, Sendable {
  public var mode: ConfigBootstrapMode
  public var script: ConfigBootstrapScriptSpec?

  public init(
    mode: ConfigBootstrapMode = .createIfMissing,
    script: ConfigBootstrapScriptSpec? = nil
  ) {
    self.mode = mode
    self.script = script
  }

  public init(from decoder: Decoder) throws {
    if let value = try? decoder.singleValueContainer() {
      if let isEnabled = try? value.decode(Bool.self) {
        mode = isEnabled ? .createIfMissing : .none
        return
      }
      if let rawMode = try? value.decode(ConfigBootstrapMode.self) {
        mode = rawMode
        return
      }
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode =
      try container.decodeIfPresent(ConfigBootstrapMode.self, forKey: .mode) ?? .createIfMissing
    script = try container.decodeIfPresent(ConfigBootstrapScriptSpec.self, forKey: .script)
  }
}

public enum ConfigBootstrapMode: String, Codable, Equatable, Sendable {
  case none
  case createIfMissing
  case mergeMissing
}
