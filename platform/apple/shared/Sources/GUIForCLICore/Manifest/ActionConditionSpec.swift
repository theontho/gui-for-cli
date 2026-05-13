import Foundation

public struct ActionConditionSpec: Codable, Equatable, Sendable {
  public var placeholder: String
  public var equals: String?
  public var notEquals: String?
  public var inValues: [String]
  public var notInValues: [String]
  public var exists: Bool?
  public var lessThan: String?
  public var lessThanOrEqual: String?
  public var greaterThan: String?
  public var greaterThanOrEqual: String?

  public init(
    placeholder: String,
    equals: String? = nil,
    notEquals: String? = nil,
    inValues: [String] = [],
    notInValues: [String] = [],
    exists: Bool? = nil,
    lessThan: String? = nil,
    lessThanOrEqual: String? = nil,
    greaterThan: String? = nil,
    greaterThanOrEqual: String? = nil
  ) {
    self.placeholder = placeholder
    self.equals = equals
    self.notEquals = notEquals
    self.inValues = inValues
    self.notInValues = notInValues
    self.exists = exists
    self.lessThan = lessThan
    self.lessThanOrEqual = lessThanOrEqual
    self.greaterThan = greaterThan
    self.greaterThanOrEqual = greaterThanOrEqual
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    placeholder = try container.decode(String.self, forKey: .placeholder)
    equals = try container.decodeIfPresent(String.self, forKey: .equals)
    notEquals = try container.decodeIfPresent(String.self, forKey: .notEquals)
    inValues = try container.decodeIfPresent([String].self, forKey: .inValues) ?? []
    notInValues = try container.decodeIfPresent([String].self, forKey: .notInValues) ?? []
    exists = try container.decodeIfPresent(Bool.self, forKey: .exists)
    lessThan = try container.decodeIfPresent(String.self, forKey: .lessThan)
    lessThanOrEqual = try container.decodeIfPresent(String.self, forKey: .lessThanOrEqual)
    greaterThan = try container.decodeIfPresent(String.self, forKey: .greaterThan)
    greaterThanOrEqual = try container.decodeIfPresent(String.self, forKey: .greaterThanOrEqual)
  }

  private enum CodingKeys: String, CodingKey {
    case placeholder
    case equals
    case notEquals
    case inValues = "in"
    case notInValues = "notIn"
    case exists
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual
  }
}
