import Foundation

public struct ControlSpec: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var label: String
  public var kind: ControlKind
  public var value: String?
  public var placeholder: String?
  public var tooltip: String?
  public var options: [ControlOption]
  public var columns: [ListColumnSpec]
  public var rows: [ListRowSpec]
  public var rowTemplate: ListRowSpec?
  public var items: [ListItemSpec]
  public var rowActions: [ActionSpec]
  public var dataSource: ScriptDataSourceSpec?
  public var configFile: ConfigFileSpec?
  public var settings: [ConfigSettingSpec]

  public init(
    id: String,
    label: String,
    kind: ControlKind,
    value: String? = nil,
    placeholder: String? = nil,
    tooltip: String? = nil,
    options: [ControlOption] = [],
    columns: [ListColumnSpec] = [],
    rows: [ListRowSpec] = [],
    rowTemplate: ListRowSpec? = nil,
    items: [ListItemSpec] = [],
    rowActions: [ActionSpec] = [],
    dataSource: ScriptDataSourceSpec? = nil,
    configFile: ConfigFileSpec? = nil,
    settings: [ConfigSettingSpec] = []
  ) {
    self.id = id
    self.label = label
    self.kind = kind
    self.value = value
    self.placeholder = placeholder
    self.tooltip = tooltip
    self.options = options
    self.columns = columns
    self.rows = rows
    self.rowTemplate = rowTemplate
    self.items = items
    self.rowActions = rowActions
    self.dataSource = dataSource
    self.configFile = configFile
    self.settings = settings
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    label = try container.decode(String.self, forKey: .label)
    kind = try container.decode(ControlKind.self, forKey: .kind)
    value = try container.decodeIfPresent(String.self, forKey: .value)
    placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
    tooltip = try container.decodeIfPresent(String.self, forKey: .tooltip)
    options = try container.decodeIfPresent([ControlOption].self, forKey: .options) ?? []
    columns = try container.decodeIfPresent([ListColumnSpec].self, forKey: .columns) ?? []
    rows = try container.decodeIfPresent([ListRowSpec].self, forKey: .rows) ?? []
    rowTemplate = try container.decodeIfPresent(ListRowSpec.self, forKey: .rowTemplate)
    items = try container.decodeIfPresent([ListItemSpec].self, forKey: .items) ?? []
    rowActions = try container.decodeIfPresent([ActionSpec].self, forKey: .rowActions) ?? []
    dataSource = try container.decodeIfPresent(ScriptDataSourceSpec.self, forKey: .dataSource)
    configFile = try container.decodeIfPresent(ConfigFileSpec.self, forKey: .configFile)
    settings = try container.decodeIfPresent([ConfigSettingSpec].self, forKey: .settings) ?? []
  }
}

public enum ControlKind: String, Codable, Equatable, Sendable {
  case text
  case path
  case dropdown
  case toggle
  case checkboxGroup
  case infoGrid
  case libraryList
  case configEditor
}

public struct ScriptDataSourceSpec: Codable, Equatable, Sendable {
  public var path: String
  public var arguments: [String]
  public var environment: [String: String]
  public var workingDirectory: String?

  public init(
    path: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    workingDirectory: String? = nil
  ) {
    self.path = path
    self.arguments = arguments
    self.environment = environment
    self.workingDirectory = workingDirectory
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try container.decode(String.self, forKey: .path)
    arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
    environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
    workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
  }
}

public struct ControlOption: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var selected: Bool
  public var status: String?

  public init(id: String, title: String, selected: Bool = false, status: String? = nil) {
    self.id = id
    self.title = title
    self.selected = selected
    self.status = status
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    selected = try container.decodeIfPresent(Bool.self, forKey: .selected) ?? false
    status = try container.decodeIfPresent(String.self, forKey: .status)
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

public struct ListItemSpec: Codable, Equatable, Sendable {
  public var values: [String: String]

  public init(values: [String: String]) {
    self.values = values
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    var values: [String: String] = [:]

    for key in container.allKeys {
      if key.stringValue == "values" {
        let nested = try container.decodeIfPresent([String: String].self, forKey: key) ?? [:]
        values.merge(nested) { _, new in new }
      } else if let value = try? container.decode(String.self, forKey: key) {
        values[key.stringValue] = value
      } else if let value = try? container.decode(Bool.self, forKey: key) {
        values[key.stringValue] = value ? "true" : "false"
      } else if let value = try? container.decode(Int.self, forKey: key) {
        values[key.stringValue] = String(value)
      } else if let value = try? container.decode(Double.self, forKey: key) {
        values[key.stringValue] = String(value)
      }
    }

    self.values = values
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: DynamicCodingKey.self)
    for (key, value) in values.sorted(by: { $0.key < $1.key }) {
      try container.encode(value, forKey: DynamicCodingKey(stringValue: key))
    }
  }
}
