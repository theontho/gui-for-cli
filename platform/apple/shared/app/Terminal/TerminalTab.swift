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
  private(set) var text: String
  private(set) var lineCount: Int
  var isRunning = false
  var status: TerminalTabStatus?

  init(
    title: String,
    command: String,
    lines: [String],
    isRunning: Bool = false,
    status: TerminalTabStatus? = nil
  ) {
    self.title = title
    self.command = command
    text = lines.joined(separator: "\n")
    lineCount = lines.count
    self.isRunning = isRunning
    self.status = status
  }

  var isMain: Bool {
    command == "main"
  }

  mutating func replaceLines(_ lines: [String]) {
    text = lines.joined(separator: "\n")
    lineCount = lines.count
  }

  mutating func appendLines(_ lines: [String]) {
    guard !lines.isEmpty else { return }
    let appendedText = lines.joined(separator: "\n")
    if text.isEmpty {
      text = appendedText
    } else {
      text.append("\n")
      text.append(appendedText)
    }
    lineCount += lines.count
  }
}
