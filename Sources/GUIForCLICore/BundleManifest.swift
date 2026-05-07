import Foundation

public struct CLIBundleManifest: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var displayName: String
  public var summary: String
  public var iconName: String
  public var iconPath: String?
  public var iconEmoji: String?
  public var sidebarIconStyle: SidebarIconStyle
  public var setup: BundleSetup
  public var pages: [BundlePage]

  public init(
    id: String,
    displayName: String,
    summary: String,
    iconName: String,
    iconPath: String? = nil,
    iconEmoji: String? = nil,
    sidebarIconStyle: SidebarIconStyle = .automatic,
    setup: BundleSetup = BundleSetup(),
    pages: [BundlePage]
  ) {
    self.id = id
    self.displayName = displayName
    self.summary = summary
    self.iconName = iconName
    self.iconPath = iconPath
    self.iconEmoji = iconEmoji
    self.sidebarIconStyle = sidebarIconStyle
    self.setup = setup
    self.pages = pages
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
    setup = try container.decodeIfPresent(BundleSetup.self, forKey: .setup) ?? BundleSetup()
    pages = try container.decodeIfPresent([BundlePage].self, forKey: .pages) ?? []
  }

  public func validate() throws {
    try BundleManifestValidator.validate(self)
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
  public var sections: [PageSection]

  public init(id: String, title: String, summary: String, sections: [PageSection]) {
    self.id = id
    self.title = title
    self.summary = summary
    self.sections = sections
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    summary = try container.decode(String.self, forKey: .summary)
    sections = try container.decode([PageSection].self, forKey: .sections)
  }
}

public struct PageSection: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String?
  public var subtitle: String?
  public var controls: [ControlSpec]
  public var actions: [ActionSpec]

  public init(
    id: String,
    title: String? = nil,
    subtitle: String? = nil,
    controls: [ControlSpec] = [],
    actions: [ActionSpec] = []
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.controls = controls
    self.actions = actions
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
    controls = try container.decodeIfPresent([ControlSpec].self, forKey: .controls) ?? []
    actions = try container.decodeIfPresent([ActionSpec].self, forKey: .actions) ?? []
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
  public var rowActions: [ActionSpec]
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
    rowActions: [ActionSpec] = [],
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
    self.rowActions = rowActions
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
    rowActions = try container.decodeIfPresent([ActionSpec].self, forKey: .rowActions) ?? []
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

public struct ControlOption: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var selected: Bool

  public init(id: String, title: String, selected: Bool = false) {
    self.id = id
    self.title = title
    self.selected = selected
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    selected = try container.decodeIfPresent(Bool.self, forKey: .selected) ?? false
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
  public var tooltip: String?

  public init(
    id: String,
    title: String? = nil,
    values: [String: String] = [:],
    status: String? = nil,
    tooltip: String? = nil
  ) {
    self.id = id
    self.title = title
    self.values = values
    self.status = status
    self.tooltip = tooltip
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    values = try container.decodeIfPresent([String: String].self, forKey: .values) ?? [:]
    status = try container.decodeIfPresent(String.self, forKey: .status)
    tooltip = try container.decodeIfPresent(String.self, forKey: .tooltip)
  }
}

public struct ConfigFileSpec: Codable, Equatable, Sendable {
  public var path: String
  public var format: ConfigFileFormat

  public init(path: String, format: ConfigFileFormat = .toml) {
    self.path = path
    self.format = format
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try container.decode(String.self, forKey: .path)
    format = try container.decodeIfPresent(ConfigFileFormat.self, forKey: .format) ?? .toml
  }
}

public enum ConfigFileFormat: String, Codable, Equatable, Sendable {
  case toml
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

  public init(
    id: String,
    key: String,
    label: String,
    kind: ControlKind = .text,
    value: String? = nil,
    placeholder: String? = nil,
    tooltip: String? = nil,
    options: [ControlOption] = []
  ) {
    self.id = id
    self.key = key
    self.label = label
    self.kind = kind
    self.value = value
    self.placeholder = placeholder
    self.tooltip = tooltip
    self.options = options
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
  }
}

public struct ActionSpec: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var title: String
  public var role: ActionRole
  public var tooltip: String?
  public var command: CommandSpec

  public init(
    id: String,
    title: String,
    role: ActionRole = .primary,
    tooltip: String? = nil,
    command: CommandSpec
  ) {
    self.id = id
    self.title = title
    self.role = role
    self.tooltip = tooltip
    self.command = command
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    role = try container.decodeIfPresent(ActionRole.self, forKey: .role) ?? .primary
    tooltip = try container.decodeIfPresent(String.self, forKey: .tooltip)
    command = try container.decode(CommandSpec.self, forKey: .command)
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

  public init(executable: String, arguments: [String] = []) {
    self.executable = executable
    self.arguments = arguments
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    executable = try container.decode(String.self, forKey: .executable)
    arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
  }

  public var displayCommand: String {
    ([executable] + arguments).joined(separator: " ")
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

    guard !manifest.pages.isEmpty else {
      throw BundleValidationError.noPages
    }

    try validateUniqueIDs(manifest.setup.steps, path: "setup.steps")
    try validateUniqueIDs(manifest.pages, path: "pages")

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
          try validateUniqueIDs(
            control.rowActions,
            path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).rowActions")
          try validateUniqueIDs(
            control.settings,
            path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).settings")
          if let configFile = control.configFile {
            try requireNonEmpty(
              configFile.path,
              path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).configFile.path"
            )
            try validateRelativePath(
              configFile.path,
              path: "pages.\(page.id).sections.\(section.id).controls.\(control.id).configFile.path"
            )
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

  private static func validateRelativePath(_ value: String, path: String) throws {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("/") || trimmed.contains("..") {
      throw BundleValidationError.invalidRelativePath(path: path, value: value)
    }
  }
}
