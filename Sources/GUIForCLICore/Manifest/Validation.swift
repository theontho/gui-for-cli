import Foundation

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

struct DynamicCodingKey: CodingKey {
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
