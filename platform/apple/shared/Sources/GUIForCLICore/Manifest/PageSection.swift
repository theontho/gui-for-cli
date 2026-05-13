import Foundation

public struct PageSection: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String?
  public var subtitle: String?
  public var iconName: String?
  public var textIcon: String?
  public var dataSource: ScriptDataSourceSpec?
  public var controls: [ControlSpec]
  public var actions: [ActionSpec]

  public init(
    id: String,
    title: String? = nil,
    subtitle: String? = nil,
    iconName: String? = nil,
    textIcon: String? = nil,
    dataSource: ScriptDataSourceSpec? = nil,
    controls: [ControlSpec] = [],
    actions: [ActionSpec] = []
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.iconName = iconName
    self.textIcon = textIcon
    self.dataSource = dataSource
    self.controls = controls
    self.actions = actions
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
    iconName =
      try container.decodeIfPresent(String.self, forKey: .iconName)
      ?? legacyContainer.decodeIfPresent(String.self, forKey: .systemImage)
    textIcon = try container.decodeIfPresent(String.self, forKey: .textIcon)
    dataSource = try container.decodeIfPresent(ScriptDataSourceSpec.self, forKey: .dataSource)
    controls = try container.decodeIfPresent([ControlSpec].self, forKey: .controls) ?? []
    actions = try container.decodeIfPresent([ActionSpec].self, forKey: .actions) ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case subtitle
    case iconName
    case textIcon
    case dataSource
    case controls
    case actions
  }

  private enum LegacyCodingKeys: String, CodingKey {
    case systemImage
  }
}
