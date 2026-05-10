import Foundation

public struct BundleLocalizationResolver: Sendable {
  private let table: BundleStringTable

  public init(table: BundleStringTable) {
    self.table = table
  }

  public func localized(_ manifest: CLIBundleManifest) throws -> CLIBundleManifest {
    var manifest = manifest
    manifest.displayName = localized(manifest.displayName)
    manifest.summary = localized(manifest.summary)

    manifest.setup.steps = manifest.setup.steps.map { step in
      var step = step
      step.label = localized(step.label)
      return step
    }

    let exitCodeOverrides = manifest.exitCodeReference.map { entry in
      var entry = entry
      entry.title = localized(entry.title)
      entry.summary = localized(entry.summary)
      return entry
    }
    manifest.exitCodeReference = CLIBundleManifest.mergedExitCodeReference(
      defaults: localizedDefaultExitCodeReference(),
      overrides: exitCodeOverrides)

    manifest.pages = manifest.pages.map { page in
      var page = page
      page.title = localized(page.title)
      page.summary = localized(page.summary)
      page.sidebarGroup = localized(page.sidebarGroup)
      page.sections = page.sections.map { section in
        var section = section
        section.title = localized(section.title)
        section.subtitle = localized(section.subtitle)
        section.controls = section.controls.map { control in
          var control = control
          control.label = localized(control.label)
          control.placeholder = localized(control.placeholder)
          control.tooltip = localized(control.tooltip)
          control.options = control.options.map { option in
            var option = option
            option.title = localized(option.title)
            option.group = localized(option.group)
            return option
          }
          control.columns = control.columns.map { column in
            var column = column
            column.title = localized(column.title)
            return column
          }
          control.rows = control.rows.map { row in
            var row = row
            row.title = localized(row.title)
            row.status = localized(row.status)
            row.tags = row.tags.map { tag in
              var tag = tag
              tag.title = localized(tag.title)
              return tag
            }
            row.tooltip = localized(row.tooltip)
            return row
          }
          if var rowTemplate = control.rowTemplate {
            rowTemplate.title = localized(rowTemplate.title)
            rowTemplate.status = localized(rowTemplate.status)
            rowTemplate.tags = rowTemplate.tags.map { tag in
              var tag = tag
              tag.title = localized(tag.title)
              return tag
            }
            rowTemplate.tooltip = localized(rowTemplate.tooltip)
            control.rowTemplate = rowTemplate
          }
          control.items = control.items.map { item in
            var item = item
            item.values = item.values.mapValues { localized($0) }
            return item
          }
          control.rowActions = control.rowActions.map { action in
            var action = action
            action.title = localized(action.title)
            action.tooltip = localized(action.tooltip)
            action.disabledTooltip = localized(action.disabledTooltip)
            action.confirm = localized(action.confirm)
            return action
          }
          control.settings = control.settings.map { setting in
            var setting = setting
            setting.label = localized(setting.label)
            setting.placeholder = localized(setting.placeholder)
            setting.tooltip = localized(setting.tooltip)
            setting.options = setting.options.map { option in
              var option = option
              option.title = localized(option.title)
              option.group = localized(option.group)
              return option
            }
            return setting
          }
          return control
        }
        section.actions = section.actions.map { action in
          var action = action
          action.title = localized(action.title)
          action.tooltip = localized(action.tooltip)
          action.disabledTooltip = localized(action.disabledTooltip)
          action.confirm = localized(action.confirm)
          return action
        }
        return section
      }
      return page
    }

    return manifest
  }

  private func localized(_ value: String?) -> String? {
    guard let value else {
      return nil
    }
    return localized(value)
  }

  private func localized(_ value: String) -> String {
    table[value] ?? value
  }

  private func localized(_ value: ActionConfirmationSpec?) -> ActionConfirmationSpec? {
    guard var value else { return nil }
    value.title = localized(value.title)
    value.message = localized(value.message)
    value.confirmButtonTitle = localized(value.confirmButtonTitle)
    value.cancelButtonTitle = localized(value.cancelButtonTitle)
    value.requiredText = localized(value.requiredText)
    value.prompt = localized(value.prompt)
    return value
  }

  private func localizedDefaultExitCodeReference() -> [ExitCodeReferenceEntry] {
    CLIBundleManifest.defaultExitCodeReference.map { entry in
      let titleKey = "exitCodes.default.\(entry.code).title"
      let summaryKey = "exitCodes.default.\(entry.code).summary"
      return ExitCodeReferenceEntry(
        code: entry.code,
        title: table[titleKey] ?? entry.title,
        summary: table[summaryKey] ?? entry.summary,
        severity: entry.severity)
    }
  }
}
