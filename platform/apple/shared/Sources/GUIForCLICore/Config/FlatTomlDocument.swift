import Foundation

public enum FlatTomlDocument {
  public static func parse(_ text: String) throws -> [String: String] {
    var values: [String: String] = [:]
    for rawLine in text.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty || line.hasPrefix("#") || !line.contains("=") {
        continue
      }
      let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let key = String(parts[0])
        .trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
      let rawValue = String(parts[1]).trimmingCharacters(in: .whitespaces)
      values[key] = parseValue(rawValue)
    }
    return values
  }

  public static func string(from pairs: [(String, String)]) -> String {
    pairs.map { key, value in "\(tomlKey(key)) = \(tomlValue(value))" }
      .joined(separator: "\n") + "\n"
  }

  public static func string(from values: [String: String]) -> String {
    string(from: values.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
  }

  private static func parseValue(_ value: String) -> String {
    guard value.hasPrefix("\""), value.hasSuffix("\"") else {
      return value
    }
    var result = ""
    var iterator = value.dropFirst().dropLast().makeIterator()
    while let character = iterator.next() {
      guard character == "\\" else {
        result.append(character)
        continue
      }
      guard let escaped = iterator.next() else { break }
      switch escaped {
      case "n": result.append("\n")
      case "r": result.append("\r")
      case "t": result.append("\t")
      case "\"": result.append("\"")
      case "\\": result.append("\\")
      default: result.append(escaped)
      }
    }
    return result
  }

  private static func tomlKey(_ key: String) -> String {
    if key.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
      return key
    }
    return tomlValue(key)
  }

  private static func tomlValue(_ value: String) -> String {
    "\""
      + value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n") + "\""
  }
}
