import Foundation

public struct ListItemSpec: Codable, Equatable, Sendable {
  public var values: [String: String]

  public init(values: [String: String]) {
    self.values = values
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    var values: [String: String] = [:]

    for key in container.allKeys {
      if key.stringValue == "values" {
        let nested = try container.decodeIfPresent([String: String].self, forKey: key) ?? [:]
        values.merge(nested) { _, new in new }
      } else if let value = try? container.decode(String.self, forKey: key) {
        values[key.stringValue] = value
      } else if let value = try? container.decode(Bool.self, forKey: key) {
        values[key.stringValue] = value ? "true" : "false"
      } else if let value = try? container.decode(Int.self, forKey: key) {
        values[key.stringValue] = String(value)
      } else if let value = try? container.decode(Double.self, forKey: key) {
        values[key.stringValue] = String(value)
      }
    }

    self.values = values
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: DynamicCodingKey.self)
    for (key, value) in values.sorted(by: { $0.key < $1.key }) {
      try container.encode(value, forKey: DynamicCodingKey(stringValue: key))
    }
  }
}
