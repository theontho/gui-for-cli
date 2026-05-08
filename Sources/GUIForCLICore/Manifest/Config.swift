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

public struct ConfigBootstrapScriptSpec: Codable, Equatable, Sendable {
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

public struct ConfigSettingSpec: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var key: String
  public var label: String
  public var kind: ControlKind
  public var value: String?
  public var placeholder: String?
  public var tooltip: String?
  public var options: [ControlOption]
  public var dataSource: ScriptDataSourceSpec?

  public init(
    id: String,
    key: String,
    label: String,
    kind: ControlKind = .text,
    value: String? = nil,
    placeholder: String? = nil,
    tooltip: String? = nil,
    options: [ControlOption] = [],
    dataSource: ScriptDataSourceSpec? = nil
  ) {
    self.id = id
    self.key = key
    self.label = label
    self.kind = kind
    self.value = value
    self.placeholder = placeholder
    self.tooltip = tooltip
    self.options = options
    self.dataSource = dataSource
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    key = try container.decode(String.self, forKey: .key)
    label = try container.decode(String.self, forKey: .label)
    kind = try container.decodeIfPresent(ControlKind.self, forKey: .kind) ?? .text
    value = try container.decodeIfPresent(String.self, forKey: .value)
    placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
    tooltip = try container.decodeIfPresent(String.self, forKey: .tooltip)
    options = try container.decodeIfPresent([ControlOption].self, forKey: .options) ?? []
    dataSource = try container.decodeIfPresent(ScriptDataSourceSpec.self, forKey: .dataSource)
  }
}
