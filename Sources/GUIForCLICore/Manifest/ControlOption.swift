import Foundation

public struct ControlOption: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var selected: Bool
  public var status: String?
  public var group: String?

  public init(
    id: String,
    title: String,
    selected: Bool = false,
    status: String? = nil,
    group: String? = nil
  ) {
    self.id = id
    self.title = title
    self.selected = selected
    self.status = status
    self.group = group
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    selected = try container.decodeIfPresent(Bool.self, forKey: .selected) ?? false
    status = try container.decodeIfPresent(String.self, forKey: .status)
    group = try container.decodeIfPresent(String.self, forKey: .group)
  }
}
