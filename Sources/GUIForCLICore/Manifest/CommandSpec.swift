import Foundation

public struct CommandSpec: Codable, Equatable, Sendable {
  public var executable: String
  public var arguments: [String]
  public var optionalArguments: [[String]]

  public init(
    executable: String, arguments: [String] = [], optionalArguments: [[String]] = []
  ) {
    self.executable = executable
    self.arguments = arguments
    self.optionalArguments = optionalArguments
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    executable = try container.decode(String.self, forKey: .executable)
    arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
    optionalArguments =
      try container.decodeIfPresent([[String]].self, forKey: .optionalArguments) ?? []
  }

  public var displayCommand: String {
    ([executable] + arguments + optionalArguments.flatMap(\.self)).joined(separator: " ")
  }
}
