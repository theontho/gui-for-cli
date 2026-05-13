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
