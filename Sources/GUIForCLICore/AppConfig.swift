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

public enum ConfigError: LocalizedError, Equatable {
  case fileExists(URL)
  case invalidDataDirectory(String)

  public var errorDescription: String? {
    switch self {
    case .fileExists(let url):
      "Config already exists at \(url.path). Use --force to overwrite it."
    case .invalidDataDirectory(let path):
      "dataDirectory must be an absolute path, got: \(path)"
    }
  }
}

public struct AppConfig: Codable, Equatable, Sendable {
  public var logLevel: LogLevel
  public var dataDirectory: String
  public var apiKey: String?

  public init(
    logLevel: LogLevel = .info,
    dataDirectory: String = AppPaths.defaultDataDirectory().path,
    apiKey: String? = nil
  ) {
    self.logLevel = logLevel
    self.dataDirectory = dataDirectory
    self.apiKey = apiKey
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    logLevel = try container.decodeIfPresent(LogLevel.self, forKey: .logLevel) ?? .info
    dataDirectory =
      try container.decodeIfPresent(String.self, forKey: .dataDirectory)
      ?? AppPaths.defaultDataDirectory().path
    apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
    try validate()
  }

  public func validate() throws {
    guard (dataDirectory as NSString).isAbsolutePath else {
      throw ConfigError.invalidDataDirectory(dataDirectory)
    }
  }

  public func redactedValues() -> [(key: String, value: String)] {
    [
      ("logLevel", logLevel.rawValue),
      ("dataDirectory", dataDirectory),
      ("apiKey", apiKey == nil ? "nil" : "<redacted>"),
    ]
  }
}
