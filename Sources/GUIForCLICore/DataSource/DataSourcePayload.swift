import Foundation

public struct DataSourcePayload: Decodable, Equatable, Sendable {
  public var options: [ControlOption]?
  public var rows: [ListRowSpec]?
  public var rowActions: [ActionSpec]?
  public var values: [String: String]?

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    options = try container.decodeIfPresent([ControlOption].self, forKey: .options)
    rows =
      try container.decodeIfPresent([ListRowSpec].self, forKey: .rows)
      ?? container.decodeIfPresent([ListRowSpec].self, forKey: .items)
    rowActions =
      try container.decodeIfPresent([ActionSpec].self, forKey: .rowActions)
      ?? container.decodeIfPresent([ActionSpec].self, forKey: .actions)
    values = try container.decodeIfPresent([String: String].self, forKey: .values)
  }

  private enum CodingKeys: String, CodingKey {
    case options
    case rows
    case items
    case rowActions
    case actions
    case values
  }
}

public struct DynamicControlData: Equatable {
  public var options: [ControlOption]?
  public var rows: [ListRowSpec]?
  public var rowActions: [ActionSpec]?

  public init(
    options: [ControlOption]? = nil, rows: [ListRowSpec]? = nil, rowActions: [ActionSpec]? = nil
  ) {
    self.options = options
    self.rows = rows
    self.rowActions = rowActions
  }

  public init(payload: DataSourcePayload) {
    self.options = payload.options
    self.rows = payload.rows
    self.rowActions = payload.rowActions
  }
}
