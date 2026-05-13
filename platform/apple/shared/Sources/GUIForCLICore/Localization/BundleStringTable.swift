import Foundation

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
