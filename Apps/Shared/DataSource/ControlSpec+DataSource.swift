import GUIForCLICore
import SwiftUI

extension ControlSpec {
  func applying(_ dynamicData: DynamicControlData) -> ControlSpec {
    var control = self
    if let options = dynamicData.options {
      control.options = options
    }
    if let rows = dynamicData.rows {
      control.rows = rows
      control.items = []
    }
    if let rowActions = dynamicData.rowActions {
      control.rowActions = rowActions
    }
    return control
  }
}
