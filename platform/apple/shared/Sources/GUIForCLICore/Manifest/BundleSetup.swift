import Foundation

public struct BundleSetup: Codable, Equatable, Sendable {
  public var steps: [SetupStep]

  public init(steps: [SetupStep] = []) {
    self.steps = steps
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    steps = try container.decodeIfPresent([SetupStep].self, forKey: .steps) ?? []
  }
}

public enum SidebarIconStyle: String, CaseIterable, Codable, Equatable, Sendable {
  case automatic
  case image
  case emoji
  case symbol
  case hidden
}
