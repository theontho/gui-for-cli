import Foundation

public struct TagSpec: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var style: TagStyle

  public init(id: String, title: String, style: TagStyle = .secondary) {
    self.id = id
    self.title = title
    self.style = style
  }

  public init(from decoder: Decoder) throws {
    if let container = try? decoder.singleValueContainer(),
      let title = try? container.decode(String.self)
    {
      id = title
      self.title = title
      style = .secondary
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id =
      try container.decodeIfPresent(String.self, forKey: .id)
      ?? container.decode(String.self, forKey: .title)
    title = try container.decode(String.self, forKey: .title)
    style = try container.decodeIfPresent(TagStyle.self, forKey: .style) ?? .secondary
  }
}

public enum TagStyle: String, Codable, Equatable, Sendable {
  case primary
  case secondary
  case success
  case warning
  case danger
}
