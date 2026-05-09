import GUIForCLICore
import SwiftUI

extension ContentView {
  /// Drains startup diagnostics (workspace bootstrapping notes, config
  /// load receipts) into the terminal once the detail pane appears.
  func flushStartupMessages() {
    let messages = startupMessages
    guard !messages.isEmpty else { return }
    startupMessages.removeAll()
    for message in messages {
      terminal.appendToMain(message)
    }
  }
}
