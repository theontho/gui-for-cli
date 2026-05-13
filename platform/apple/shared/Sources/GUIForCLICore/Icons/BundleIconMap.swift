import Foundation

public struct BundleIconMap: Equatable, Sendable {
  public static let sfSymbolsSource = "sf-symbols"
  public static let windowsSource = "windows"
  public static let bootstrapSource = "bootstrap"
  public static let emojiSource = "emoji"

  public var sources: [String: [String: String]]

  public init(sources: [String: [String: String]] = [:]) {
    self.sources = sources
  }

  public init(tomlData: Data) throws {
    guard let text = String(data: tomlData, encoding: .utf8) else {
      throw BundleIconMapError.invalidLine(1, "Icon map file is not UTF-8.")
    }
    self.sources = try Self.parse(text)
  }

  public func value(for key: String?, source: String) -> String? {
    guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
      return nil
    }
    return sources[source]?[key]
  }

  public func resolving(_ key: String?, source: String, fallbackToKey: Bool = false) -> String? {
    value(for: key, source: source) ?? (fallbackToKey ? key?.nonEmpty : nil)
  }

  public func merging(_ overrides: BundleIconMap) -> BundleIconMap {
    var merged = sources
    for (source, values) in overrides.sources {
      merged[source, default: [:]].merge(values) { _, override in override }
    }
    return BundleIconMap(sources: merged)
  }

  private static func parse(_ text: String) throws -> [String: [String: String]] {
    var sources: [String: [String: String]] = [:]
    var currentSource: String?
    let lines = text.components(separatedBy: .newlines)

    for (offset, rawLine) in lines.enumerated() {
      let lineNumber = offset + 1
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty || line.hasPrefix("#") {
        continue
      }

      if line.hasPrefix("[") && line.hasSuffix("]") {
        let source = String(line.dropFirst().dropLast())
          .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
          throw BundleIconMapError.invalidLine(lineNumber, rawLine)
        }
        currentSource = source
        sources[source, default: [:]] = sources[source, default: [:]]
        continue
      }

      guard let source = currentSource,
        let equals = line.firstIndex(of: "=")
      else {
        throw BundleIconMapError.invalidLine(lineNumber, rawLine)
      }

      let rawKey = line[..<equals].trimmingCharacters(in: .whitespaces)
      let key = unquoteKey(String(rawKey))
      let rawValue = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
      sources[source, default: [:]][key] = try parseStringValue(
        rawValue,
        lineNumber: lineNumber,
        rawLine: rawLine)
    }

    return sources
  }

  private static func unquoteKey(_ key: String) -> String {
    if key.hasPrefix("\""), key.hasSuffix("\"") {
      return String(key.dropFirst().dropLast())
    }
    return key
  }

  private static func parseStringValue(
    _ rawValue: String,
    lineNumber: Int,
    rawLine: String
  ) throws -> String {
    guard rawValue.hasPrefix("\"") else {
      throw BundleIconMapError.invalidLine(lineNumber, rawLine)
    }
    let characters = Array(rawValue)
    var cursor = 1
    var closing: Int?
    while cursor < characters.count {
      let character = characters[cursor]
      if character == "\\" {
        cursor += 2
        continue
      }
      if character == "\"" {
        closing = cursor
        break
      }
      cursor += 1
    }
    guard let closing else {
      throw BundleIconMapError.invalidLine(lineNumber, rawLine)
    }
    let trailing = String(characters[(closing + 1)...]).trimmingCharacters(in: .whitespaces)
    if !trailing.isEmpty && !trailing.hasPrefix("#") {
      throw BundleIconMapError.invalidLine(lineNumber, rawLine)
    }
    return try unescape(String(characters[1..<closing]), lineNumber: lineNumber, rawLine: rawLine)
  }

  private static func unescape(
    _ value: String,
    lineNumber: Int,
    rawLine: String
  ) throws -> String {
    let characters = Array(value)
    var result = ""
    var index = 0
    while index < characters.count {
      let character = characters[index]
      guard character == "\\" else {
        result.append(character)
        index += 1
        continue
      }
      index += 1
      guard index < characters.count else {
        throw BundleIconMapError.invalidLine(lineNumber, rawLine)
      }
      let escaped = characters[index]
      index += 1
      switch escaped {
      case "n": result.append("\n")
      case "r": result.append("\r")
      case "t": result.append("\t")
      case "\"": result.append("\"")
      case "\\": result.append("\\")
      case "u", "U":
        let count = escaped == "u" ? 4 : 8
        guard index + count <= characters.count else {
          throw BundleIconMapError.invalidLine(lineNumber, rawLine)
        }
        let hex = String(characters[index..<(index + count)])
        guard let scalarValue = UInt32(hex, radix: 16),
          let scalar = UnicodeScalar(scalarValue)
        else {
          throw BundleIconMapError.invalidLine(lineNumber, rawLine)
        }
        result.unicodeScalars.append(scalar)
        index += count
      default:
        throw BundleIconMapError.invalidLine(lineNumber, rawLine)
      }
    }
    return result
  }
}

public enum BundleIconMapError: LocalizedError, Equatable {
  case invalidLine(Int, String)

  public var errorDescription: String? {
    switch self {
    case .invalidLine(let line, let text):
      "Invalid icon map TOML at line \(line): \(text)"
    }
  }
}
