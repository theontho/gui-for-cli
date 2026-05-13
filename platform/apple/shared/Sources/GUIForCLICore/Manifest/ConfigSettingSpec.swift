import Foundation

public struct ConfigSettingSpec: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var key: String
  public var label: String
  public var kind: ControlKind
  public var value: String?
  public var placeholder: String?
  public var tooltip: String?
  public var options: [ControlOption]
  public var dataSource: ScriptDataSourceSpec?

  public init(
    id: String,
    key: String,
    label: String,
    kind: ControlKind = .text,
    value: String? = nil,
    placeholder: String? = nil,
    tooltip: String? = nil,
    options: [ControlOption] = [],
    dataSource: ScriptDataSourceSpec? = nil
  ) {
    self.id = id
    self.key = key
    self.label = label
    self.kind = kind
    self.value = value
    self.placeholder = placeholder
    self.tooltip = tooltip
    self.options = options
    self.dataSource = dataSource
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    key = try container.decode(String.self, forKey: .key)
    label = try container.decode(String.self, forKey: .label)
    kind = try container.decodeIfPresent(ControlKind.self, forKey: .kind) ?? .text
    value = try container.decodeIfPresent(String.self, forKey: .value)
    placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
    tooltip = try container.decodeIfPresent(String.self, forKey: .tooltip)
    options = try container.decodeIfPresent([ControlOption].self, forKey: .options) ?? []
    dataSource = try container.decodeIfPresent(ScriptDataSourceSpec.self, forKey: .dataSource)
  }
}
