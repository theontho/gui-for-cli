import Foundation

public struct SetupCommand: Equatable, Identifiable, Sendable {
  public var id: String
  public var label: String
  public var kind: SetupStepKind
  public var executable: String
  public var arguments: [String]
  public var environment: [String: String]
  public var workingDirectory: URL
  public var optional: Bool
  public var requiresAdmin: Bool

  public init(
    id: String,
    label: String,
    kind: SetupStepKind,
    executable: String,
    arguments: [String],
    environment: [String: String],
    workingDirectory: URL,
    optional: Bool,
    requiresAdmin: Bool = false
  ) {
    self.id = id
    self.label = label
    self.kind = kind
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.workingDirectory = workingDirectory
    self.optional = optional
    self.requiresAdmin = requiresAdmin
  }

  public var displayCommand: String {
    let renderedCommand = ([executable] + arguments).map(Self.shellQuoted).joined(separator: " ")
    return requiresAdmin ? "sudo \(renderedCommand)" : renderedCommand
  }

  static func shellQuoted(_ value: String) -> String {
    guard !value.isEmpty, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
      !value.contains("'")
    else {
      return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
    return value
  }
}

public enum SetupPlanError: LocalizedError, Equatable {
  case unsafeRelativePath(String)
  case missingScript(URL)
  case unsupportedPlatform(String)

  public var errorDescription: String? {
    switch self {
    case .unsafeRelativePath(let path):
      "Setup path must be relative and stay inside the bundle: \(path)"
    case .missingScript(let url):
      "Setup script does not exist: \(url.path)"
    case .unsupportedPlatform(let platform):
      "Setup command execution is not available on \(platform)."
    }
  }
}
