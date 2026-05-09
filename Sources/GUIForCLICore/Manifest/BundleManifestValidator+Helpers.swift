import Foundation

extension BundleManifestValidator {
  static func requireNonEmpty(_ value: String, path: String) throws {
    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw BundleValidationError.emptyField(path: path)
    }
  }

  static func validateUniqueIDs<T: Identifiable>(_ values: [T], path: String) throws
  where T.ID == String {
    var seen = Set<String>()
    for value in values {
      if seen.contains(value.id) {
        throw BundleValidationError.duplicateID(path: path, id: value.id)
      }
      seen.insert(value.id)
    }
  }

  static func validateUniqueValues(_ values: [String], path: String) throws {
    var seen = Set<String>()
    for value in values {
      if seen.contains(value) {
        throw BundleValidationError.duplicateID(path: path, id: value)
      }
      seen.insert(value)
    }
  }

  static func validateUniqueExitCodes(_ entries: [ExitCodeReferenceEntry], path: String)
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

  static func validateRelativePath(_ value: String, path: String) throws {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("/") || trimmed.contains("..") {
      throw BundleValidationError.invalidRelativePath(path: path, value: value)
    }
  }

  static func validateConfigFilePath(_ value: String, path: String) throws {
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

  static func validateDataSource(_ value: ScriptDataSourceSpec, path: String) throws {
    try requireNonEmpty(value.path, path: "\(path).path")
    try validateBundledScriptPath(value.path, path: "\(path).path")
    if let workingDirectory = value.workingDirectory {
      try validateBundledScriptPath(workingDirectory, path: "\(path).workingDirectory")
    }
  }

  static func validateBundledScriptPath(_ value: String, path: String) throws {
    try validateRelativePath(value, path: path)
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("~") || trimmed.contains("{{") || trimmed.contains("}}") {
      throw BundleValidationError.invalidRelativePath(path: path, value: value)
    }
  }

  static func validateActionCondition(_ value: ActionConditionSpec, path: String) throws {
    try requireNonEmpty(value.placeholder, path: "\(path).placeholder")
    if value.equals == nil && value.notEquals == nil && value.inValues.isEmpty
      && value.notInValues.isEmpty && value.exists == nil
      && value.lessThan == nil && value.lessThanOrEqual == nil
      && value.greaterThan == nil && value.greaterThanOrEqual == nil
    {
      try requireNonEmpty("", path: path)
    }
  }

  static func validateActionConfirmation(_ value: ActionConfirmationSpec?, path: String)
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
