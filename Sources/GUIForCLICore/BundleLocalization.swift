import Foundation

public enum BundleLocalizationError: LocalizedError, Equatable {
  case invalidLine(Int, String)
  case unterminatedMultilineString(String)

  public var errorDescription: String? {
    switch self {
    case .invalidLine(let line, let text):
      "Invalid localization TOML at line \(line): \(text)"
    case .unterminatedMultilineString(let key):
      "Unterminated multiline localization string: \(key)"
    }
  }
}

public struct BundleStringTable: Equatable, Sendable {
  public var values: [String: String]

  public init(values: [String: String] = [:]) {
    self.values = values
  }

  public init(tomlData: Data) throws {
    guard let text = String(data: tomlData, encoding: .utf8) else {
      throw BundleLocalizationError.invalidLine(1, "Localization file is not UTF-8.")
    }
    self.values = try Self.parse(text)
  }

  public subscript(key: String) -> String? {
    values[key]
  }

  public func merging(_ overrides: BundleStringTable) -> BundleStringTable {
    BundleStringTable(values: values.merging(overrides.values) { _, override in override })
  }

  private static func parse(_ text: String) throws -> [String: String] {
    var values: [String: String] = [:]
    let lines = text.components(separatedBy: .newlines)
    var index = 0

    while index < lines.count {
      let rawLine = lines[index]
      let lineNumber = index + 1
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      index += 1

      if line.isEmpty || line.hasPrefix("#") {
        continue
      }
      if line.hasPrefix("[") && line.hasSuffix("]") {
        throw BundleLocalizationError.invalidLine(lineNumber, rawLine)
      }

      guard let equals = line.firstIndex(of: "=") else {
        throw BundleLocalizationError.invalidLine(lineNumber, rawLine)
      }

      let rawKey = line[..<equals].trimmingCharacters(in: .whitespaces)
      let key = unquoteKey(String(rawKey))
      var rawValue = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)

      if rawValue.hasPrefix("\"\"\"") {
        rawValue.removeFirst(3)
        var collected: [String] = []
        if let end = rawValue.range(of: "\"\"\"") {
          collected.append(String(rawValue[..<end.lowerBound]))
        } else {
          collected.append(String(rawValue))
          var foundEnd = false
          while index < lines.count {
            let nextLine = lines[index]
            index += 1
            if let end = nextLine.range(of: "\"\"\"") {
              collected.append(String(nextLine[..<end.lowerBound]))
              foundEnd = true
              break
            }
            collected.append(nextLine)
          }
          guard foundEnd else {
            throw BundleLocalizationError.unterminatedMultilineString(key)
          }
        }
        if collected.first == "" {
          collected.removeFirst()
        }
        if collected.last == "" {
          collected.removeLast()
        }
        values[key] = collected.joined(separator: "\n")
        continue
      }

      guard rawValue.hasPrefix("\"") else {
        throw BundleLocalizationError.invalidLine(lineNumber, rawLine)
      }
      // Find the closing quote, honoring backslash escapes, then allow an
      // optional trailing `#` comment (used for translator hints such as
      // `# i18n-ignore`).
      let scalars = Array(rawValue)
      var cursor = 1
      var closing: Int? = nil
      while cursor < scalars.count {
        let ch = scalars[cursor]
        if ch == "\\" {
          cursor += 2
          continue
        }
        if ch == "\"" {
          closing = cursor
          break
        }
        cursor += 1
      }
      guard let closingIndex = closing else {
        throw BundleLocalizationError.invalidLine(lineNumber, rawLine)
      }
      let trailing = String(scalars[(closingIndex + 1)...]).trimmingCharacters(in: .whitespaces)
      if !trailing.isEmpty && !trailing.hasPrefix("#") {
        throw BundleLocalizationError.invalidLine(lineNumber, rawLine)
      }
      let inner = String(scalars[1..<closingIndex])
      values[key] = unescape(inner)
    }

    return values
  }

  private static func unquoteKey(_ key: String) -> String {
    if key.hasPrefix("\""), key.hasSuffix("\"") {
      return String(key.dropFirst().dropLast())
    }
    return key
  }

  private static func unescape(_ value: String) -> String {
    var result = ""
    var iterator = value.makeIterator()
    while let character = iterator.next() {
      guard character == "\\" else {
        result.append(character)
        continue
      }
      guard let escaped = iterator.next() else {
        result.append("\\")
        break
      }
      switch escaped {
      case "n": result.append("\n")
      case "r": result.append("\r")
      case "t": result.append("\t")
      case "\"": result.append("\"")
      case "\\": result.append("\\")
      default:
        result.append("\\")
        result.append(escaped)
      }
    }
    return result
  }
}

public struct BundleLocalizationOption: Equatable, Identifiable, Sendable {
  public var code: String
  public var displayName: String

  public var id: String { code }

  public init(code: String, displayName: String) {
    self.code = code
    self.displayName = displayName
  }
}

public enum BundleInterfaceLayoutDirection: String, Equatable, Sendable {
  case leftToRight = "ltr"
  case rightToLeft = "rtl"
}

public struct BundleLocalizationLabels: Equatable, Sendable {
  public var languageSectionTitle: String
  public var languagePickerLabel: String
  public var languageSearchPlaceholder: String
  public var languageSystemDefaultLabel: String
  public var layoutDirection: BundleInterfaceLayoutDirection
  public var terminalMainTabTitle: String
  public var terminalCommandOutputLabel: String
  public var chooseButtonTitle: String
  public var pathPickerErrorTitle: String
  public var settingsFileLabel: String
  public var loadButtonTitle: String
  public var actionsColumnTitle: String
  public var loadingTitle: String
  public var refreshingTitle: String
  public var retryButtonTitle: String
  public var libraryStatusLabels: [String: String]
  public var libraryTagLabels: [String: String]

  public init(
    languageSectionTitle: String = "Interface Language",
    languagePickerLabel: String = "Language",
    languageSearchPlaceholder: String = "Search languages",
    languageSystemDefaultLabel: String = "Use system default",
    layoutDirection: BundleInterfaceLayoutDirection = .leftToRight,
    terminalMainTabTitle: String = "Main",
    terminalCommandOutputLabel: String = "Command output",
    chooseButtonTitle: String = "Choose...",
    pathPickerErrorTitle: String = "Could not choose path",
    settingsFileLabel: String = "Settings File",
    loadButtonTitle: String = "Load",
    actionsColumnTitle: String = "Actions",
    loadingTitle: String = "Loading...",
    refreshingTitle: String = "Refreshing...",
    retryButtonTitle: String = "Retry",
    libraryStatusLabels: [String: String] = [
      "installed": "installed",
      "unindexed": "unindexed",
      "incomplete": "incomplete",
      "missing": "missing",
    ],
    libraryTagLabels: [String: String] = [
      "recommended": "Recommended"
    ]
  ) {
    self.languageSectionTitle = languageSectionTitle
    self.languagePickerLabel = languagePickerLabel
    self.languageSearchPlaceholder = languageSearchPlaceholder
    self.languageSystemDefaultLabel = languageSystemDefaultLabel
    self.layoutDirection = layoutDirection
    self.terminalMainTabTitle = terminalMainTabTitle
    self.terminalCommandOutputLabel = terminalCommandOutputLabel
    self.chooseButtonTitle = chooseButtonTitle
    self.pathPickerErrorTitle = pathPickerErrorTitle
    self.settingsFileLabel = settingsFileLabel
    self.loadButtonTitle = loadButtonTitle
    self.actionsColumnTitle = actionsColumnTitle
    self.loadingTitle = loadingTitle
    self.refreshingTitle = refreshingTitle
    self.retryButtonTitle = retryButtonTitle
    self.libraryStatusLabels = libraryStatusLabels
    self.libraryTagLabels = libraryTagLabels
  }

  public init(table: BundleStringTable?) {
    self.init(
      languageSectionTitle: table?["language.setting.title"] ?? "Interface Language",
      languagePickerLabel: table?["language.setting.label"] ?? "Language",
      languageSearchPlaceholder: table?["language.setting.searchPlaceholder"]
        ?? "Search languages",
      languageSystemDefaultLabel: table?["language.setting.systemDefault"]
        ?? "Use system default",
      layoutDirection: Self.layoutDirection(from: table?["language.layoutDirection"]),
      terminalMainTabTitle: table?["app.terminal.mainTab.title"] ?? "Main",
      terminalCommandOutputLabel: table?["app.terminal.commandOutput.label"] ?? "Command output",
      chooseButtonTitle: table?["app.pathPicker.chooseButton.title"] ?? "Choose...",
      pathPickerErrorTitle: table?["app.pathPicker.error.title"] ?? "Could not choose path",
      settingsFileLabel: table?["app.settingsFile.label"] ?? "Settings File",
      loadButtonTitle: table?["app.loadButton.title"] ?? "Load",
      actionsColumnTitle: table?["app.actionsColumn.title"] ?? "Actions",
      loadingTitle: table?["app.loading.title"] ?? "Loading...",
      refreshingTitle: table?["app.refreshing.title"] ?? "Refreshing...",
      retryButtonTitle: table?["app.retryButton.title"] ?? "Retry",
      libraryStatusLabels: [
        "installed": table?["library.status.installed"] ?? "installed",
        "unindexed": table?["library.status.unindexed"] ?? "unindexed",
        "incomplete": table?["library.status.incomplete"] ?? "incomplete",
        "missing": table?["library.status.missing"] ?? "missing",
      ],
      libraryTagLabels: [
        "recommended": table?["library.tags.recommended"] ?? "Recommended"
      ])
  }

  private static func layoutDirection(from value: String?) -> BundleInterfaceLayoutDirection {
    switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "rtl", "right-to-left", "righttoleft":
      return .rightToLeft
    default:
      return .leftToRight
    }
  }
}

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
