import Foundation

public enum BundleValidationError: LocalizedError, Equatable {
  case emptyField(path: String)
  case noPages
  case noSections(pageID: String)
  case noCommand(actionID: String)
  case duplicateID(path: String, id: String)
  case invalidRelativePath(path: String, value: String)
  case invalidTextIcon(path: String, value: String)

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
    case .invalidTextIcon(let path, let value):
      "Text icon at \(path) must be 1 or 2 characters: \(value)"
    }
  }
}
