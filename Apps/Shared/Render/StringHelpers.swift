import GUIForCLICore
import SwiftUI

extension Optional where Wrapped == String {
  var nonEmpty: String? {
    guard let value = self else { return nil }
    return value.nonEmpty
  }
}

extension String {
  var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
