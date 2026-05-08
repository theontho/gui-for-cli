import Foundation

public struct ActionSpec: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var role: ActionRole
  public var tooltip: String?
  public var iconName: String?
  public var iconEmoji: String?
  public var iconOnly: Bool
  public var visibleWhen: [ActionConditionSpec]
  public var disabledWhen: [ActionConditionSpec]
  public var disabledTooltip: String?
  public var precheck: ActionPrecheckSpec?
  public var confirm: ActionConfirmationSpec?
  public var command: CommandSpec

  public init(
    id: String,
    title: String,
    role: ActionRole = .primary,
    tooltip: String? = nil,
    iconName: String? = nil,
    iconEmoji: String? = nil,
    iconOnly: Bool = false,
    visibleWhen: [ActionConditionSpec] = [],
    disabledWhen: [ActionConditionSpec] = [],
    disabledTooltip: String? = nil,
    precheck: ActionPrecheckSpec? = nil,
    confirm: ActionConfirmationSpec? = nil,
    command: CommandSpec
  ) {
    self.id = id
    self.title = title
    self.role = role
    self.tooltip = tooltip
    self.iconName = iconName
    self.iconEmoji = iconEmoji
    self.iconOnly = iconOnly
    self.visibleWhen = visibleWhen
    self.disabledWhen = disabledWhen
    self.disabledTooltip = disabledTooltip
    self.precheck = precheck
    self.confirm = confirm
    self.command = command
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    role = try container.decodeIfPresent(ActionRole.self, forKey: .role) ?? .primary
    tooltip = try container.decodeIfPresent(String.self, forKey: .tooltip)
    iconName =
      try container.decodeIfPresent(String.self, forKey: .iconName)
      ?? legacyContainer.decodeIfPresent(String.self, forKey: .systemImage)
    iconEmoji = try container.decodeIfPresent(String.self, forKey: .iconEmoji)
    iconOnly = try container.decodeIfPresent(Bool.self, forKey: .iconOnly) ?? false
    visibleWhen =
      try container.decodeIfPresent([ActionConditionSpec].self, forKey: .visibleWhen) ?? []
    disabledWhen =
      try container.decodeIfPresent([ActionConditionSpec].self, forKey: .disabledWhen) ?? []
    disabledTooltip = try container.decodeIfPresent(String.self, forKey: .disabledTooltip)
    precheck = try container.decodeIfPresent(ActionPrecheckSpec.self, forKey: .precheck)
    confirm = try container.decodeIfPresent(ActionConfirmationSpec.self, forKey: .confirm)
    command = try container.decode(CommandSpec.self, forKey: .command)
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case role
    case tooltip
    case iconName
    case iconEmoji
    case iconOnly
    case visibleWhen
    case disabledWhen
    case disabledTooltip
    case precheck
    case confirm
    case command
  }

  private enum LegacyCodingKeys: String, CodingKey {
    case systemImage
  }
}

/// Pre-flight checks that run before an action can fire. Currently supports
/// disk-space verification; future iterations may add memory or network
/// reachability checks.
public struct ActionPrecheckSpec: Codable, Equatable, Sendable {
  /// Required free space at `diskSpacePath`, expressed as gigabytes. The
  /// value is interpolated as a placeholder expression and then evaluated as
  /// a numeric expression (e.g. `"{{bam_path.fileSizeGB}} * 6"`).
  public var diskSpaceGB: String?
  /// Path whose containing volume is checked for free space. Defaults to
  /// `{{out_dir}}` if present, falling back to `{{bundleWorkspace}}`.
  public var diskSpacePath: String?
  /// Optional warning message override (interpolated). Defaults to a
  /// generic "Need X GB free, only Y GB available" message synthesised by
  /// the renderer using the labels table.
  public var warningMessage: String?

  public init(
    diskSpaceGB: String? = nil,
    diskSpacePath: String? = nil,
    warningMessage: String? = nil
  ) {
    self.diskSpaceGB = diskSpaceGB
    self.diskSpacePath = diskSpacePath
    self.warningMessage = warningMessage
  }
}

public struct ActionConfirmationSpec: Codable, Equatable, Sendable {
  public var title: String
  public var message: String?
  public var confirmButtonTitle: String
  public var cancelButtonTitle: String
  public var requiredText: String?
  public var prompt: String?

  public init(
    title: String,
    message: String? = nil,
    confirmButtonTitle: String = "Continue",
    cancelButtonTitle: String = "Cancel",
    requiredText: String? = nil,
    prompt: String? = nil
  ) {
    self.title = title
    self.message = message
    self.confirmButtonTitle = confirmButtonTitle
    self.cancelButtonTitle = cancelButtonTitle
    self.requiredText = requiredText
    self.prompt = prompt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    message = try container.decodeIfPresent(String.self, forKey: .message)
    confirmButtonTitle =
      try container.decodeIfPresent(String.self, forKey: .confirmButtonTitle) ?? "Continue"
    cancelButtonTitle =
      try container.decodeIfPresent(String.self, forKey: .cancelButtonTitle) ?? "Cancel"
    requiredText = try container.decodeIfPresent(String.self, forKey: .requiredText)
    prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
  }

  private enum CodingKeys: String, CodingKey {
    case title
    case message
    case confirmButtonTitle
    case cancelButtonTitle
    case requiredText
    case prompt
  }
}

public struct ActionConditionSpec: Codable, Equatable, Sendable {
  public var placeholder: String
  public var equals: String?
  public var notEquals: String?
  public var inValues: [String]
  public var notInValues: [String]
  public var exists: Bool?
  public var lessThan: String?
  public var lessThanOrEqual: String?
  public var greaterThan: String?
  public var greaterThanOrEqual: String?

  public init(
    placeholder: String,
    equals: String? = nil,
    notEquals: String? = nil,
    inValues: [String] = [],
    notInValues: [String] = [],
    exists: Bool? = nil,
    lessThan: String? = nil,
    lessThanOrEqual: String? = nil,
    greaterThan: String? = nil,
    greaterThanOrEqual: String? = nil
  ) {
    self.placeholder = placeholder
    self.equals = equals
    self.notEquals = notEquals
    self.inValues = inValues
    self.notInValues = notInValues
    self.exists = exists
    self.lessThan = lessThan
    self.lessThanOrEqual = lessThanOrEqual
    self.greaterThan = greaterThan
    self.greaterThanOrEqual = greaterThanOrEqual
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    placeholder = try container.decode(String.self, forKey: .placeholder)
    equals = try container.decodeIfPresent(String.self, forKey: .equals)
    notEquals = try container.decodeIfPresent(String.self, forKey: .notEquals)
    inValues = try container.decodeIfPresent([String].self, forKey: .inValues) ?? []
    notInValues = try container.decodeIfPresent([String].self, forKey: .notInValues) ?? []
    exists = try container.decodeIfPresent(Bool.self, forKey: .exists)
    lessThan = try container.decodeIfPresent(String.self, forKey: .lessThan)
    lessThanOrEqual = try container.decodeIfPresent(String.self, forKey: .lessThanOrEqual)
    greaterThan = try container.decodeIfPresent(String.self, forKey: .greaterThan)
    greaterThanOrEqual = try container.decodeIfPresent(String.self, forKey: .greaterThanOrEqual)
  }

  private enum CodingKeys: String, CodingKey {
    case placeholder
    case equals
    case notEquals
    case inValues = "in"
    case notInValues = "notIn"
    case exists
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual
  }
}

public enum ActionRole: String, Codable, Equatable, Sendable {
  case primary
  case secondary
  case destructive
}

public struct CommandSpec: Codable, Equatable, Sendable {
  public var executable: String
  public var arguments: [String]
  public var optionalArguments: [[String]]

  public init(
    executable: String, arguments: [String] = [], optionalArguments: [[String]] = []
  ) {
    self.executable = executable
    self.arguments = arguments
    self.optionalArguments = optionalArguments
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    executable = try container.decode(String.self, forKey: .executable)
    arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
    optionalArguments =
      try container.decodeIfPresent([[String]].self, forKey: .optionalArguments) ?? []
  }

  public var displayCommand: String {
    ([executable] + arguments + optionalArguments.flatMap(\.self)).joined(separator: " ")
  }
}
