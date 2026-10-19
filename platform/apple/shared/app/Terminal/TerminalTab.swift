import Foundation
import Observation

/// One terminal tab. Its running/status state and its output are observed
/// separately, so streaming output never re-renders the tab strip or the page.
@MainActor
@Observable
final class TerminalTab: Identifiable {
  enum Kind {
    case main
    case action
    case setup
  }

  let id = UUID()
  let kind: Kind
  var title: String
  let command: String
  var isRunning: Bool
  var status: TerminalTabStatus?
  let output: TerminalOutputBuffer

  init(
    kind: Kind,
    title: String,
    command: String,
    lines: [String],
    isRunning: Bool = false,
    lineLimit: Int = TerminalOutputBuffer.defaultLineLimit
  ) {
    self.kind = kind
    self.title = title
    self.command = command
    self.isRunning = isRunning
    output = TerminalOutputBuffer(lines: lines, lineLimit: lineLimit)
  }

  var isMain: Bool { kind == .main }
}
