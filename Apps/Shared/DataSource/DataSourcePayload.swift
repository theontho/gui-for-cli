import GUIForCLICore
import SwiftUI

struct DataSourcePayload: Decodable, Equatable, Sendable {
  var options: [ControlOption]?
  var rows: [ListRowSpec]?
  var rowActions: [ActionSpec]?
  var values: [String: String]?

  init(from decoder: Decoder) throws {
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

struct DynamicControlData: Equatable {
  var options: [ControlOption]?
  var rows: [ListRowSpec]?
  var rowActions: [ActionSpec]?

  init(options: [ControlOption]? = nil, rows: [ListRowSpec]? = nil, rowActions: [ActionSpec]? = nil)
  {
    self.options = options
    self.rows = rows
    self.rowActions = rowActions
  }

  init(payload: DataSourcePayload) {
    self.options = payload.options
    self.rows = payload.rows
    self.rowActions = payload.rowActions
  }
}
