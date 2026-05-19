import Foundation

public struct SetupStep: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var kind: SetupStepKind
  public var label: String
  public var value: String
  public var arguments: [String]
  public var environment: [String: String]
  public var workingDirectory: String?
  public var optional: Bool
  public var toolName: String?
  public var toolVersion: String?
  public var toolVersionFile: String?

  public init(
    id: String,
    kind: SetupStepKind,
    label: String,
    value: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    workingDirectory: String? = nil,
    optional: Bool = false,
    toolName: String? = nil,
    toolVersion: String? = nil,
    toolVersionFile: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.label = label
    self.value = value
    self.arguments = arguments
    self.environment = environment
    self.workingDirectory = workingDirectory
    self.optional = optional
    self.toolName = toolName
    self.toolVersion = toolVersion
    self.toolVersionFile = toolVersionFile
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    kind = try container.decode(SetupStepKind.self, forKey: .kind)
    label = try container.decode(String.self, forKey: .label)
    value = try container.decode(String.self, forKey: .value)
    arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
    environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
    workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
    optional = try container.decodeIfPresent(Bool.self, forKey: .optional) ?? false
    toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
    toolVersion = try container.decodeIfPresent(String.self, forKey: .toolVersion)
    toolVersionFile = try container.decodeIfPresent(String.self, forKey: .toolVersionFile)
  }
}

public enum SetupStepKind: String, Codable, Equatable, Sendable {
  case bundledScript
  case setupScript
  case pathTool
  case homebrewPackage
  case pixiInstall
  case pixiRun
}
