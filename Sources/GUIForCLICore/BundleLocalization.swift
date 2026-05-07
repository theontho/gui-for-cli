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

      guard rawValue.hasPrefix("\""), rawValue.hasSuffix("\"") else {
        throw BundleLocalizationError.invalidLine(lineNumber, rawLine)
      }
      rawValue.removeFirst()
      rawValue.removeLast()
      values[key] = unescape(String(rawValue))
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

    manifest.pages = manifest.pages.map { page in
      var page = page
      page.title = localized(page.title)
      page.summary = localized(page.summary)
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
          return control
        }
        section.actions = section.actions.map { action in
          var action = action
          action.title = localized(action.title)
          action.tooltip = localized(action.tooltip)
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
}
