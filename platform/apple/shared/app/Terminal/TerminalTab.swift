import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct TerminalTab: Identifiable {
  let id = UUID()
  var title: String
  var command: String
  var lines: [String]
  var isRunning = false
  var status: TerminalTabStatus?

  var isMain: Bool {
    command == "main"
  }
}
