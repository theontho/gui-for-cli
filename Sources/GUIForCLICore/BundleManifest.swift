import Foundation

public struct CLIBundleManifest: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var displayName: String
  public var summary: String
  public var iconName: String
  public var iconPath: String?
  public var iconEmoji: String?
  public var sidebarIconStyle: SidebarIconStyle
  public var terminalTextDirection: TerminalTextDirection
  public var setup: BundleSetup
  public var exitCodeReference: [ExitCodeReferenceEntry]
  public var pages: [BundlePage]
  public var pageFiles: [String]

  public init(
    id: String,
    displayName: String,
    summary: String,
    iconName: String,
    iconPath: String? = nil,
    iconEmoji: String? = nil,
    sidebarIconStyle: SidebarIconStyle = .automatic,
    terminalTextDirection: TerminalTextDirection = .leftToRight,
    setup: BundleSetup = BundleSetup(),
    exitCodeReference: [ExitCodeReferenceEntry] = [],
    pages: [BundlePage],
    pageFiles: [String] = []
  ) {
    self.id = id
    self.displayName = displayName
    self.summary = summary
    self.iconName = iconName
    self.iconPath = iconPath
    self.iconEmoji = iconEmoji
    self.sidebarIconStyle = sidebarIconStyle
    self.terminalTextDirection = terminalTextDirection
    self.setup = setup
    self.exitCodeReference = exitCodeReference
    self.pages = pages
    self.pageFiles = pageFiles
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    displayName = try container.decode(String.self, forKey: .displayName)
    summary = try container.decode(String.self, forKey: .summary)
    iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "terminal"
    iconPath = try container.decodeIfPresent(String.self, forKey: .iconPath)
    iconEmoji = try container.decodeIfPresent(String.self, forKey: .iconEmoji)
    sidebarIconStyle =
      try container.decodeIfPresent(SidebarIconStyle.self, forKey: .sidebarIconStyle) ?? .automatic
    terminalTextDirection =
      try container.decodeIfPresent(TerminalTextDirection.self, forKey: .terminalTextDirection)
      ?? .leftToRight
    setup = try container.decodeIfPresent(BundleSetup.self, forKey: .setup) ?? BundleSetup()
    exitCodeReference =
      try container.decodeIfPresent([ExitCodeReferenceEntry].self, forKey: .exitCodeReference) ?? []
    if let inlinePages = try? container.decode([BundlePage].self, forKey: .pages) {
      pages = inlinePages
      pageFiles = []
    } else {
      pages = []
      pageFiles = try container.decodeIfPresent([String].self, forKey: .pages) ?? []
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(displayName, forKey: .displayName)
    try container.encode(summary, forKey: .summary)
    try container.encode(iconName, forKey: .iconName)
    try container.encodeIfPresent(iconPath, forKey: .iconPath)
    try container.encodeIfPresent(iconEmoji, forKey: .iconEmoji)
    try container.encode(sidebarIconStyle, forKey: .sidebarIconStyle)
    try container.encode(terminalTextDirection, forKey: .terminalTextDirection)
    try container.encode(setup, forKey: .setup)
    if !exitCodeReference.isEmpty {
      try container.encode(exitCodeReference, forKey: .exitCodeReference)
    }
    if pages.isEmpty {
      try container.encode(pageFiles, forKey: .pages)
    } else {
      try container.encode(pages, forKey: .pages)
    }
  }

  public func validate() throws {
    try BundleManifestValidator.validate(self)
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case displayName
    case summary
    case iconName
    case iconPath
    case iconEmoji
    case sidebarIconStyle
    case terminalTextDirection
    case setup
    case exitCodeReference
    case pages
  }
}

public enum TerminalTextDirection: String, CaseIterable, Codable, Equatable, Sendable {
  case leftToRight = "ltr"
  case rightToLeft = "rtl"
}

public struct ExitCodeReferenceEntry: Codable, Equatable, Sendable {
  public var code: Int32
  public var title: String
  public var summary: String
  public var severity: ExitCodeSeverity

  public init(
    code: Int32,
    title: String,
    summary: String,
    severity: ExitCodeSeverity = .error
  ) {
    self.code = code
    self.title = title
    self.summary = summary
    self.severity = severity
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    code = try container.decode(Int32.self, forKey: .code)
    title = try container.decode(String.self, forKey: .title)
    summary = try container.decode(String.self, forKey: .summary)
    severity = try container.decodeIfPresent(ExitCodeSeverity.self, forKey: .severity) ?? .error
  }

  private enum CodingKeys: String, CodingKey {
    case code
    case title
    case summary
    case severity
  }
}

public enum ExitCodeSeverity: String, Codable, Equatable, Sendable {
  case warning
  case error
}

public extension CLIBundleManifest {
  static let defaultExitCodeReference: [ExitCodeReferenceEntry] = [
    ExitCodeReferenceEntry(
      code: 1,
      title: "General command failure",
      summary: "The command reported a generic failure. Review the output for details."),
    ExitCodeReferenceEntry(
      code: 2,
      title: "Command-line usage error",
      summary:
        "The command arguments were not accepted. Check required inputs, paths, and selected options before running again."
    ),
    ExitCodeReferenceEntry(
      code: 126,
      title: "Command found but not executable",
      summary:
        "The command or script exists but could not be executed. Check file permissions and whether setup completed successfully."
    ),
    ExitCodeReferenceEntry(
      code: 127,
      title: "Command not found",
      summary:
        "The command runner could not find the executable. Run setup for this bundle and verify the runtime workspace exists."
    ),
    ExitCodeReferenceEntry(
      code: 130,
      title: "Command cancelled",
      summary:
        "The command was interrupted by the user. Any partial output or temporary files may need to be cleaned up before retrying.",
      severity: .warning),
  ]

  var effectiveExitCodeReference: [ExitCodeReferenceEntry] {
    Self.mergedExitCodeReference(overrides: exitCodeReference)
  }

  static func mergedExitCodeReference(
    defaults: [ExitCodeReferenceEntry] = defaultExitCodeReference,
    overrides: [ExitCodeReferenceEntry]
  ) -> [ExitCodeReferenceEntry] {
    var entriesByCode = Dictionary(
      defaults.map { ($0.code, $0) },
      uniquingKeysWith: { first, _ in first })
    for entry in overrides {
      entriesByCode[entry.code] = entry
    }
    return entriesByCode.values.sorted { $0.code < $1.code }
  }
}

public enum SidebarIconStyle: String, CaseIterable, Codable, Equatable, Sendable {
  case automatic
  case image
  case emoji
  case symbol
  case hidden
}

public struct BundleSetup: Codable, Equatable, Sendable {
  public var steps: [SetupStep]

  public init(steps: [SetupStep] = []) {
    self.steps = steps
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    steps = try container.decodeIfPresent([SetupStep].self, forKey: .steps) ?? []
  }
}

public struct SetupStep: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var kind: SetupStepKind
  public var label: String
  public var value: String
  public var arguments: [String]
  public var environment: [String: String]
  public var workingDirectory: String?
  public var optional: Bool

  public init(
    id: String,
    kind: SetupStepKind,
    label: String,
    value: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    workingDirectory: String? = nil,
    optional: Bool = false
  ) {
    self.id = id
    self.kind = kind
    self.label = label
    self.value = value
    self.arguments = arguments
    self.environment = environment
    self.workingDirectory = workingDirectory
    self.optional = optional
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    kind = try container.decode(SetupStepKind.self, forKey: .kind)
    label = try container.decode(String.self, forKey: .label)
    value = try container.decode(String.self, forKey: .value)
    arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
    environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
    workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
    optional = try container.decodeIfPresent(Bool.self, forKey: .optional) ?? false
  }
}

public enum SetupStepKind: String, Codable, Equatable, Sendable {
  case bundledScript
  case setupScript
  case pathTool
  case homebrewPackage
  case pixiInstall
  case pixiRun
}

public struct BundlePage: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var summary: String
  public var iconName: String?
  public var iconEmoji: String?
  public var sidebarGroup: String?
  public var sections: [PageSection]

  public init(
    id: String,
    title: String,
    summary: String,
    iconName: String? = nil,
    iconEmoji: String? = nil,
    sidebarGroup: String? = nil,
    sections: [PageSection]
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.iconName = iconName
    self.iconEmoji = iconEmoji
    self.sidebarGroup = sidebarGroup
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
    iconEmoji = try container.decodeIfPresent(String.self, forKey: .iconEmoji)
    sidebarGroup = try container.decodeIfPresent(String.self, forKey: .sidebarGroup)
    sections = try container.decode([PageSection].self, forKey: .sections)
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case summary
    case iconName
    case iconEmoji
    case sidebarGroup
    case sections
  }

  private enum LegacyCodingKeys: String, CodingKey {
    case systemImage
  }
}

public struct PageSection: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String?
  public var subtitle: String?
  public var iconName: String?
  public var iconEmoji: String?
  public var dataSource: ScriptDataSourceSpec?
  public var controls: [ControlSpec]
  public var actions: [ActionSpec]

  public init(
    id: String,
    title: String? = nil,
    subtitle: String? = nil,
    iconName: String? = nil,
    iconEmoji: String? = nil,
    dataSource: ScriptDataSourceSpec? = nil,
    controls: [ControlSpec] = [],
    actions: [ActionSpec] = []
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.iconName = iconName
    self.iconEmoji = iconEmoji
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
    iconEmoji = try container.decodeIfPresent(String.self, forKey: .iconEmoji)
    dataSource = try container.decodeIfPresent(ScriptDataSourceSpec.self, forKey: .dataSource)
    controls = try container.decodeIfPresent([ControlSpec].self, forKey: .controls) ?? []
    actions = try container.decodeIfPresent([ActionSpec].self, forKey: .actions) ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case subtitle
    case iconName
    case iconEmoji
    case dataSource
    case controls
    case actions
  }

  private enum LegacyCodingKeys: String, CodingKey {
    case systemImage
  }
}

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

public struct ConfigFileSpec: Codable, Equatable, Sendable {
  public var path: String
  public var format: ConfigFileFormat
  public var bootstrap: ConfigBootstrapSpec?

  public init(
    path: String,
    format: ConfigFileFormat = .toml,
    bootstrap: ConfigBootstrapSpec? = nil
  ) {
    self.path = path
    self.format = format
    self.bootstrap = bootstrap
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try container.decode(String.self, forKey: .path)
    format = try container.decodeIfPresent(ConfigFileFormat.self, forKey: .format) ?? .toml
    bootstrap = try container.decodeIfPresent(ConfigBootstrapSpec.self, forKey: .bootstrap)
  }
}

public enum ConfigFileFormat: String, Codable, Equatable, Sendable {
  case toml
}

public struct ConfigBootstrapSpec: Codable, Equatable, Sendable {
  public var mode: ConfigBootstrapMode
  public var script: ConfigBootstrapScriptSpec?

  public init(
    mode: ConfigBootstrapMode = .createIfMissing,
    script: ConfigBootstrapScriptSpec? = nil
  ) {
    self.mode = mode
    self.script = script
  }

  public init(from decoder: Decoder) throws {
    if let value = try? decoder.singleValueContainer() {
      if let isEnabled = try? value.decode(Bool.self) {
        mode = isEnabled ? .createIfMissing : .none
        return
      }
      if let rawMode = try? value.decode(ConfigBootstrapMode.self) {
        mode = rawMode
        return
      }
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode =
      try container.decodeIfPresent(ConfigBootstrapMode.self, forKey: .mode) ?? .createIfMissing
    script = try container.decodeIfPresent(ConfigBootstrapScriptSpec.self, forKey: .script)
  }
}

public enum ConfigBootstrapMode: String, Codable, Equatable, Sendable {
  case none
  case createIfMissing
  case mergeMissing
}

public struct ConfigBootstrapScriptSpec: Codable, Equatable, Sendable {
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

public enum BundleValidationError: LocalizedError, Equatable {
  case emptyField(path: String)
  case noPages
  case noSections(pageID: String)
  case noCommand(actionID: String)
  case duplicateID(path: String, id: String)
  case invalidRelativePath(path: String, value: String)

  public var errorDescription: String? {
    switch self {
    case .emptyField(let path):
      "Required field is empty: \(path)"
    case .noPages:
      "Bundle manifest must define at least one page."
    case .noSections(let pageID):
      "Page '\(pageID)' must define at least one section."
    case .noCommand(let actionID):
      "Action '\(actionID)' must define a command executable."
    case .duplicateID(let path, let id):
      "Duplicate id '\(id)' at \(path)."
    case .invalidRelativePath(let path, let value):
      "Invalid relative path at \(path): \(value)"
    }
  }
}

public enum BundleManifestValidator {
  public static func validate(_ manifest: CLIBundleManifest) throws {
    try requireNonEmpty(manifest.id, path: "id")
    try requireNonEmpty(manifest.displayName, path: "displayName")
    try requireNonEmpty(manifest.summary, path: "summary")
    if let iconPath = manifest.iconPath {
      try validateRelativePath(iconPath, path: "iconPath")
    }
    if let iconEmoji = manifest.iconEmoji {
      try requireNonEmpty(iconEmoji, path: "iconEmoji")
    }

    guard !manifest.pages.isEmpty || !manifest.pageFiles.isEmpty else {
      throw BundleValidationError.noPages
    }

    try validateUniqueIDs(manifest.setup.steps, path: "setup.steps")
    try validateUniqueIDs(manifest.pages, path: "pages")
    try validateUniqueValues(manifest.pageFiles, path: "pages")
    try validateUniqueExitCodes(manifest.exitCodeReference, path: "exitCodeReference")
    for entry in manifest.exitCodeReference {
      try requireNonEmpty(entry.title, path: "exitCodeReference.\(entry.code).title")
      try requireNonEmpty(entry.summary, path: "exitCodeReference.\(entry.code).summary")
    }

    for setupStep in manifest.setup.steps {
      try requireNonEmpty(setupStep.id, path: "setup.steps.\(setupStep.id).id")
      try requireNonEmpty(setupStep.label, path: "setup.steps.\(setupStep.id).label")
      try requireNonEmpty(setupStep.value, path: "setup.steps.\(setupStep.id).value")
      if setupStep.kind == .bundledScript || setupStep.kind == .setupScript {
        try validateRelativePath(setupStep.value, path: "setup.steps.\(setupStep.id).value")
      }
      if let workingDirectory = setupStep.workingDirectory {
        try validateRelativePath(
          workingDirectory, path: "setup.steps.\(setupStep.id).workingDirectory")
      }
    }

    for pageFile in manifest.pageFiles {
      try requireNonEmpty(pageFile, path: "pages")
      try validateRelativePath(pageFile, path: "pages")
      if pageFile.contains("/") {
        throw BundleValidationError.invalidRelativePath(path: "pages", value: pageFile)
      }
    }

    for page in manifest.pages {
      try requireNonEmpty(page.id, path: "pages.\(page.id).id")
      try requireNonEmpty(page.title, path: "pages.\(page.id).title")
      try requireNonEmpty(page.summary, path: "pages.\(page.id).summary")
      guard !page.sections.isEmpty else {
        throw BundleValidationError.noSections(pageID: page.id)
      }
      try validateUniqueIDs(page.sections, path: "pages.\(page.id).sections")

      for section in page.sections {
        try requireNonEmpty(section.id, path: "pages.\(page.id).sections.\(section.id).id")
        if let dataSource = section.dataSource {
          try validateDataSource(
            dataSource, path: "pages.\(page.id).sections.\(section.id).dataSource")
        }
        try validateUniqueIDs(
          section.controls, path: "pages.\(page.id).sections.\(section.id).controls")
        try validateUniqueIDs(
          section.actions, path: "pages.\(page.id).sections.\(section.id).actions")

        for control in section.controls {
          try requireNonEmpty(
            control.id, path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).id")
          try requireNonEmpty(
            control.label,
            path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).label")
          try validateUniqueIDs(
            control.options,
            path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).options")
          try validateUniqueIDs(
            control.columns,
            path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).columns")
          try validateUniqueIDs(
            control.rows,
            path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).rows")
          if let rowTemplate = control.rowTemplate {
            try requireNonEmpty(
              rowTemplate.id,
              path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).rowTemplate.id"
            )
          }
          try validateUniqueIDs(
            control.rowActions,
            path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).rowActions")
          if let dataSource = control.dataSource {
            try validateDataSource(
              dataSource,
              path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).dataSource")
          }
          try validateUniqueIDs(
            control.settings,
            path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).settings")
          if let configFile = control.configFile {
            try requireNonEmpty(
              configFile.path,
              path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).configFile.path"
            )
            try validateConfigFilePath(
              configFile.path,
              path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).configFile.path"
            )
            if let script = configFile.bootstrap?.script {
              try requireNonEmpty(
                script.path,
                path:
                  "pages.\(page.id).sections.\(section.id).controls.\(control.id).configFile.bootstrap.script.path"
              )
              try validateRelativePath(
                script.path,
                path:
                  "pages.\(page.id).sections.\(section.id).controls.\(control.id).configFile.bootstrap.script.path"
              )
              if let workingDirectory = script.workingDirectory {
                try validateRelativePath(
                  workingDirectory,
                  path:
                    "pages.\(page.id).sections.\(section.id).controls.\(control.id).configFile.bootstrap.script.workingDirectory"
                )
              }
            }
          }
          for column in control.columns {
            try requireNonEmpty(
              column.title,
              path:
                "pages.\(page.id).sections.\(section.id).controls.\(control.id).columns.\(column.id).title"
            )
          }
          for rowAction in control.rowActions {
            try requireNonEmpty(
              rowAction.title,
              path:
                "pages.\(page.id).sections.\(section.id).controls.\(control.id).rowActions.\(rowAction.id).title"
            )
            guard
              !rowAction.command.executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
              throw BundleValidationError.noCommand(actionID: rowAction.id)
            }
            for (index, condition) in rowAction.visibleWhen.enumerated() {
              try validateActionCondition(
                condition,
                path:
                  "pages.\(page.id).sections.\(section.id).controls.\(control.id).rowActions.\(rowAction.id).visibleWhen.\(index)"
              )
            }
            for (index, condition) in rowAction.disabledWhen.enumerated() {
              try validateActionCondition(
                condition,
                path:
                  "pages.\(page.id).sections.\(section.id).controls.\(control.id).rowActions.\(rowAction.id).disabledWhen.\(index)"
              )
            }
            try validateActionConfirmation(
              rowAction.confirm,
              path:
                "pages.\(page.id).sections.\(section.id).controls.\(control.id).rowActions.\(rowAction.id).confirm"
            )
          }
          for setting in control.settings {
            try requireNonEmpty(
              setting.key,
              path:
                "pages.\(page.id).sections.\(section.id).controls.\(control.id).settings.\(setting.id).key"
            )
            try requireNonEmpty(
              setting.label,
              path:
                "pages.\(page.id).sections.\(section.id).controls.\(control.id).settings.\(setting.id).label"
            )
            try validateUniqueIDs(
              setting.options,
              path:
                "pages.\(page.id).sections.\(section.id).controls.\(control.id).settings.\(setting.id).options"
            )
            if let dataSource = setting.dataSource {
              try validateDataSource(
                dataSource,
                path:
                  "pages.\(page.id).sections.\(section.id).controls.\(control.id).settings.\(setting.id).dataSource"
              )
            }
          }
        }

        for action in section.actions {
          try requireNonEmpty(
            action.id, path: "pages.\(page.id).sections.\(section.id).actions.\(action.id).id")
          try requireNonEmpty(
            action.title,
            path: "pages.\(page.id).sections.\(section.id).actions.\(action.id).title")
          guard !action.command.executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          else {
            throw BundleValidationError.noCommand(actionID: action.id)
          }
          for (index, condition) in action.visibleWhen.enumerated() {
            try validateActionCondition(
              condition,
              path:
                "pages.\(page.id).sections.\(section.id).actions.\(action.id).visibleWhen.\(index)"
            )
          }
          for (index, condition) in action.disabledWhen.enumerated() {
            try validateActionCondition(
              condition,
              path:
                "pages.\(page.id).sections.\(section.id).actions.\(action.id).disabledWhen.\(index)"
            )
          }
          try validateActionConfirmation(
            action.confirm,
            path: "pages.\(page.id).sections.\(section.id).actions.\(action.id).confirm")
        }
      }
    }
  }

  private static func requireNonEmpty(_ value: String, path: String) throws {
    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw BundleValidationError.emptyField(path: path)
    }
  }

  private static func validateUniqueIDs<T: Identifiable>(_ values: [T], path: String) throws
  where T.ID == String {
    var seen = Set<String>()
    for value in values {
      if seen.contains(value.id) {
        throw BundleValidationError.duplicateID(path: path, id: value.id)
      }
      seen.insert(value.id)
    }
  }

  private static func validateUniqueValues(_ values: [String], path: String) throws {
    var seen = Set<String>()
    for value in values {
      if seen.contains(value) {
        throw BundleValidationError.duplicateID(path: path, id: value)
      }
      seen.insert(value)
    }
  }

  private static func validateUniqueExitCodes(_ entries: [ExitCodeReferenceEntry], path: String)
    throws
  {
    var seen = Set<Int32>()
    for entry in entries {
      if seen.contains(entry.code) {
        throw BundleValidationError.duplicateID(path: path, id: "\(entry.code)")
      }
      seen.insert(entry.code)
    }
  }

  private static func validateRelativePath(_ value: String, path: String) throws {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("/") || trimmed.contains("..") {
      throw BundleValidationError.invalidRelativePath(path: path, value: value)
    }
  }

  private static func validateConfigFilePath(_ value: String, path: String) throws {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let allowedPrefixes = [
      "{{bundleRoot}}/", "{{bundleWorkspace}}/", "{{home}}/", "{{configHome}}/",
      "{{userConfig}}/", "{{applicationSupport}}/", "{{appConfig}}/", "~/",
    ]
    let hasAllowedPrefix = allowedPrefixes.contains { trimmed.hasPrefix($0) }
    if trimmed.hasPrefix("/") || trimmed.contains("..")
      || (trimmed.hasPrefix("{{") && !hasAllowedPrefix)
    {
      throw BundleValidationError.invalidRelativePath(path: path, value: value)
    }
  }

  private static func validateDataSource(_ value: ScriptDataSourceSpec, path: String) throws {
    try requireNonEmpty(value.path, path: "\(path).path")
    try validateBundledScriptPath(value.path, path: "\(path).path")
    if let workingDirectory = value.workingDirectory {
      try validateBundledScriptPath(workingDirectory, path: "\(path).workingDirectory")
    }
  }

  private static func validateBundledScriptPath(_ value: String, path: String) throws {
    try validateRelativePath(value, path: path)
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("~") || trimmed.contains("{{") || trimmed.contains("}}") {
      throw BundleValidationError.invalidRelativePath(path: path, value: value)
    }
  }

  private static func validateActionCondition(_ value: ActionConditionSpec, path: String) throws {
    try requireNonEmpty(value.placeholder, path: "\(path).placeholder")
    if value.equals == nil && value.notEquals == nil && value.inValues.isEmpty
      && value.notInValues.isEmpty && value.exists == nil
      && value.lessThan == nil && value.lessThanOrEqual == nil
      && value.greaterThan == nil && value.greaterThanOrEqual == nil
    {
      try requireNonEmpty("", path: path)
    }
  }

  private static func validateActionConfirmation(_ value: ActionConfirmationSpec?, path: String)
    throws
  {
    guard let value else { return }
    try requireNonEmpty(value.title, path: "\(path).title")
    try requireNonEmpty(value.confirmButtonTitle, path: "\(path).confirmButtonTitle")
    try requireNonEmpty(value.cancelButtonTitle, path: "\(path).cancelButtonTitle")
    if let requiredText = value.requiredText {
      try requireNonEmpty(requiredText, path: "\(path).requiredText")
    }
    if let prompt = value.prompt {
      try requireNonEmpty(prompt, path: "\(path).prompt")
    }
  }
}

private struct DynamicCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int?

  init(stringValue: String) {
    self.stringValue = stringValue
  }

  init(intValue: Int) {
    self.stringValue = String(intValue)
    self.intValue = intValue
  }
}
