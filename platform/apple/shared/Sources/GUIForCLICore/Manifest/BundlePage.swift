import Foundation

public struct BundlePage: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var summary: String
  public var iconName: String?
  public var textIcon: String?
  public var sidebarGroup: String?
  public var sidebarPlacement: SidebarPlacement
  public var sections: [PageSection]

  public init(
    id: String,
    title: String,
    summary: String,
    iconName: String? = nil,
    textIcon: String? = nil,
    sidebarGroup: String? = nil,
    sidebarPlacement: SidebarPlacement = .primary,
    sections: [PageSection]
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.iconName = iconName
    self.textIcon = textIcon
    self.sidebarGroup = sidebarGroup
    self.sidebarPlacement = sidebarPlacement
    self.sections = sections
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    summary = try container.decode(String.self, forKey: .summary)
    iconName =
      try container.decodeIfPresent(String.self, forKey: .iconName)
      ?? legacyContainer.decodeIfPresent(String.self, forKey: .systemImage)
    textIcon = try container.decodeIfPresent(String.self, forKey: .textIcon)
    sidebarGroup = try container.decodeIfPresent(String.self, forKey: .sidebarGroup)
    sidebarPlacement =
      try container.decodeIfPresent(SidebarPlacement.self, forKey: .sidebarPlacement) ?? .primary
    sections = try container.decode([PageSection].self, forKey: .sections)
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case summary
    case iconName
    case textIcon
    case sidebarGroup
    case sidebarPlacement
    case sections
  }

  private enum LegacyCodingKeys: String, CodingKey {
    case systemImage
  }
}

public enum SidebarPlacement: String, Codable, Equatable, Sendable {
  case primary
  case bottom
}
