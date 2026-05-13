import Foundation

public struct ExitCodeReferenceEntry: Codable, Equatable, Sendable {
  public var code: Int32
  public var title: String
  public var summary: String
  public var severity: ExitCodeSeverity

  public init(
    code: Int32,
    title: String,
    summary: String,
    severity: ExitCodeSeverity = .error
  ) {
    self.code = code
    self.title = title
    self.summary = summary
    self.severity = severity
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    code = try container.decode(Int32.self, forKey: .code)
    title = try container.decode(String.self, forKey: .title)
    summary = try container.decode(String.self, forKey: .summary)
    severity = try container.decodeIfPresent(ExitCodeSeverity.self, forKey: .severity) ?? .error
  }

  private enum CodingKeys: String, CodingKey {
    case code
    case title
    case summary
    case severity
  }
}

public enum ExitCodeSeverity: String, Codable, Equatable, Sendable {
  case warning
  case error
}
