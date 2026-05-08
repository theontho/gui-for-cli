import Foundation

public enum LogLevel: String, CaseIterable, Codable, Sendable {
  case debug = "DEBUG"
  case info = "INFO"
  case warning = "WARNING"
  case error = "ERROR"

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self).uppercased()

    guard let value = LogLevel(rawValue: rawValue) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid log level: \(rawValue)"
      )
    }

    self = value
  }

  public var severity: Int {
    switch self {
    case .debug: 10
    case .info: 20
    case .warning: 30
    case .error: 40
    }
  }
}
