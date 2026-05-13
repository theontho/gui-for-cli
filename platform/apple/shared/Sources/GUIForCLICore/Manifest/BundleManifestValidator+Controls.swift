import Foundation

extension BundleManifestValidator {
  static func validateControl(_ control: ControlSpec, basePath sectionPath: String) throws {
    let basePath = "\(sectionPath).controls.\(control.id)"
    try requireNonEmpty(control.id, path: "\(basePath).id")
    try requireNonEmpty(control.label, path: "\(basePath).label")
    try validateUniqueIDs(control.options, path: "\(basePath).options")
    try validateUniqueIDs(control.columns, path: "\(basePath).columns")
    try validateUniqueIDs(control.rows, path: "\(basePath).rows")
    if let rowTemplate = control.rowTemplate {
      try requireNonEmpty(rowTemplate.id, path: "\(basePath).rowTemplate.id")
    }
    try validateUniqueIDs(control.rowActions, path: "\(basePath).rowActions")
    if let dataSource = control.dataSource {
      try validateDataSource(dataSource, path: "\(basePath).dataSource")
    }
    try validateUniqueIDs(control.settings, path: "\(basePath).settings")
    if let configFile = control.configFile {
      try validateConfigFile(configFile, basePath: basePath)
    }
    for column in control.columns {
      try requireNonEmpty(column.title, path: "\(basePath).columns.\(column.id).title")
    }
    for rowAction in control.rowActions {
      try validateRowAction(rowAction, basePath: "\(basePath).rowActions.\(rowAction.id)")
    }
    for setting in control.settings {
      try validateSetting(setting, basePath: "\(basePath).settings.\(setting.id)")
    }
  }

  private static func validateConfigFile(_ configFile: ConfigFileSpec, basePath: String) throws {
    try requireNonEmpty(configFile.path, path: "\(basePath).configFile.path")
    try validateConfigFilePath(configFile.path, path: "\(basePath).configFile.path")
    if let script = configFile.bootstrap?.script {
      try requireNonEmpty(script.path, path: "\(basePath).configFile.bootstrap.script.path")
      try validateRelativePath(
        script.path, path: "\(basePath).configFile.bootstrap.script.path")
      if let workingDirectory = script.workingDirectory {
        try validateRelativePath(
          workingDirectory,
          path: "\(basePath).configFile.bootstrap.script.workingDirectory")
      }
    }
  }

  private static func validateRowAction(_ rowAction: ActionSpec, basePath: String) throws {
    try requireNonEmpty(rowAction.title, path: "\(basePath).title")
    try validateTextIcon(rowAction.textIcon, path: "\(basePath).textIcon")
    guard !rowAction.command.executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw BundleValidationError.noCommand(actionID: rowAction.id)
    }
    for (index, condition) in rowAction.visibleWhen.enumerated() {
      try validateActionCondition(condition, path: "\(basePath).visibleWhen.\(index)")
    }
    for (index, condition) in rowAction.disabledWhen.enumerated() {
      try validateActionCondition(condition, path: "\(basePath).disabledWhen.\(index)")
    }
    try validateActionConfirmation(rowAction.confirm, path: "\(basePath).confirm")
  }

  private static func validateSetting(_ setting: ConfigSettingSpec, basePath: String) throws {
    try requireNonEmpty(setting.key, path: "\(basePath).key")
    try requireNonEmpty(setting.label, path: "\(basePath).label")
    try validateUniqueIDs(setting.options, path: "\(basePath).options")
    if let dataSource = setting.dataSource {
      try validateDataSource(dataSource, path: "\(basePath).dataSource")
    }
  }
}
