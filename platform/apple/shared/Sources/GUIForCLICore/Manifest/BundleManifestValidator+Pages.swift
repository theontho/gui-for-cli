import Foundation

extension BundleManifestValidator {
  static func validatePage(_ page: BundlePage) throws {
    try requireNonEmpty(page.id, path: "pages.\(page.id).id")
    try requireNonEmpty(page.title, path: "pages.\(page.id).title")
    try requireNonEmpty(page.summary, path: "pages.\(page.id).summary")
    guard !page.sections.isEmpty else {
      throw BundleValidationError.noSections(pageID: page.id)
    }
    try validateUniqueIDs(page.sections, path: "pages.\(page.id).sections")

    for section in page.sections {
      try validateSection(section, pageID: page.id)
    }
  }

  static func validateSection(_ section: PageSection, pageID: String) throws {
    let basePath = "pages.\(pageID).sections.\(section.id)"
    try requireNonEmpty(section.id, path: "\(basePath).id")
    if let dataSource = section.dataSource {
      try validateDataSource(dataSource, path: "\(basePath).dataSource")
    }
    try validateUniqueIDs(section.controls, path: "\(basePath).controls")
    try validateUniqueIDs(section.actions, path: "\(basePath).actions")

    for control in section.controls {
      try validateControl(control, basePath: basePath)
    }
    for action in section.actions {
      try validateAction(action, basePath: "\(basePath).actions.\(action.id)")
    }
  }

  static func validateAction(_ action: ActionSpec, basePath: String) throws {
    try requireNonEmpty(action.id, path: "\(basePath).id")
    try requireNonEmpty(action.title, path: "\(basePath).title")
    guard !action.command.executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw BundleValidationError.noCommand(actionID: action.id)
    }
    for (index, condition) in action.visibleWhen.enumerated() {
      try validateActionCondition(condition, path: "\(basePath).visibleWhen.\(index)")
    }
    for (index, condition) in action.disabledWhen.enumerated() {
      try validateActionCondition(condition, path: "\(basePath).disabledWhen.\(index)")
    }
    try validateActionConfirmation(action.confirm, path: "\(basePath).confirm")
  }
}
