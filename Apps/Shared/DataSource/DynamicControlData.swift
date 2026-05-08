import GUIForCLICore
import SwiftUI

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
