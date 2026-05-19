import Foundation

public struct ActionSpec: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var role: ActionRole
  public var tooltip: String?
  public var iconName: String?
  public var textIcon: String?
  public var iconOnly: Bool
  public var estimatedDurationMinutes: Int?
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
    textIcon: String? = nil,
    iconOnly: Bool = false,
    estimatedDurationMinutes: Int? = nil,
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
    self.textIcon = textIcon
    self.iconOnly = iconOnly
    self.estimatedDurationMinutes = estimatedDurationMinutes
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
    textIcon = try container.decodeIfPresent(String.self, forKey: .textIcon)
    iconOnly = try container.decodeIfPresent(Bool.self, forKey: .iconOnly) ?? false
    estimatedDurationMinutes = try container.decodeIfPresent(
      Int.self, forKey: .estimatedDurationMinutes)
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
    case textIcon
    case iconOnly
    case estimatedDurationMinutes
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

public enum ActionRole: String, Codable, Equatable, Sendable {
  case primary
  case secondary
  case destructive
}
