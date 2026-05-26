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
  public var platforms: [String]

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
    toolVersionFile: String? = nil,
    platforms: [String] = []
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
    self.platforms = platforms
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
    platforms = try container.decodeIfPresent([String].self, forKey: .platforms) ?? []
  }
}

public enum SetupPlatform: String, CaseIterable, Sendable {
  case macos
  case windows
  case linux
  case posix

  public static var current: SetupPlatform {
    #if os(macOS)
      .macos
    #elseif os(Windows)
      .windows
    #elseif os(Linux)
      .linux
    #else
      .posix
    #endif
  }

  public static func alias(_ value: String) -> SetupPlatform? {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "darwin", "mac", "macos":
      .macos
    case "win", "win32", "windows":
      .windows
    case "linux":
      .linux
    case "posix":
      .posix
    default:
      nil
    }
  }
}

extension SetupStep {
  public func applies(to platform: SetupPlatform = .current) -> Bool {
    guard !platforms.isEmpty else { return true }
    return platforms.compactMap(SetupPlatform.alias).contains { candidate in
      candidate.matches(platform)
    }
  }
}

extension SetupPlatform {
  fileprivate func matches(_ platform: SetupPlatform) -> Bool {
    if self == .posix { return platform != .windows }
    return self == platform
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
