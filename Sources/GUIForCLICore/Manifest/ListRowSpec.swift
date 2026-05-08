import Foundation

public struct ListRowSpec: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String?
  public var values: [String: String]
  public var status: String?
  public var tags: [TagSpec]
  public var tooltip: String?

  public init(
    id: String,
    title: String? = nil,
    values: [String: String] = [:],
    status: String? = nil,
    tags: [TagSpec] = [],
    tooltip: String? = nil
  ) {
    self.id = id
    self.title = title
    self.values = values
    self.status = status
    self.tags = tags
    self.tooltip = tooltip
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    values = try container.decodeIfPresent([String: String].self, forKey: .values) ?? [:]
    status = try container.decodeIfPresent(String.self, forKey: .status)
    tags = try container.decodeIfPresent([TagSpec].self, forKey: .tags) ?? []
    tooltip = try container.decodeIfPresent(String.self, forKey: .tooltip)
  }
}

public struct ListColumnSpec: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}
