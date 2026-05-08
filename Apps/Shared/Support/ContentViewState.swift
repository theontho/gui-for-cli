import GUIForCLICore
import SwiftUI

struct InitialConfigValues {
  var values: [String: String]
  var messages: [String]
}

struct ConfigSettingBinding {
  var control: ControlSpec
  var setting: ConfigSettingSpec
}
