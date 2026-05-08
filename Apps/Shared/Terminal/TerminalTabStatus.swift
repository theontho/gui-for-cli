import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct TerminalTabStatus {
  var title: String
  var blurb: String
  var detail: String
  var symbolName: String
  var accessibilityLabel: String
  var severity: TerminalTabStatusSeverity

  var tint: Color {
    switch severity {
    case .warning:
      .orange
    case .error:
      .red
    case .cancelled:
      .yellow
    }
  }

  static func exitFailure(
    exitCode: Int32,
    command: String,
    severity: TerminalTabStatusSeverity,
    reference: ExitCodeReferenceEntry?
  ) -> TerminalTabStatus {
    let resolvedSeverity = reference?.severity.terminalSeverity ?? severity
    let title = reference?.title ?? "Exit code \(exitCode)"
    let summary =
      reference?.summary
      ?? "The command exited with a non-zero status. Check the command output for details."
    return TerminalTabStatus(
      title: title,
      blurb: summary,
      detail: "\(command) exited with code \(exitCode).",
      symbolName: resolvedSeverity == .warning
        ? "exclamationmark.triangle.fill" : "xmark.octagon.fill",
      accessibilityLabel: "Command exited with code \(exitCode)",
      severity: resolvedSeverity)
  }

  static func processError(
    command: String,
    message: String,
    severity: TerminalTabStatusSeverity = .error
  ) -> TerminalTabStatus {
    TerminalTabStatus(
      title: severity == .warning ? "Command warning" : "Command failed",
      blurb: "The command could not complete.",
      detail: "\(command)\n\(message)",
      symbolName: severity == .warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill",
      accessibilityLabel: severity == .warning ? "Command warning" : "Command failed",
      severity: severity)
  }

  static func cancelled(command: String, reference: ExitCodeReferenceEntry?) -> TerminalTabStatus {
    let summary =
      reference?.summary
      ?? "The command was cancelled before it finished. Partial output may have been produced."
    return TerminalTabStatus(
      title: reference?.title ?? "Command cancelled",
      blurb: summary,
      detail: "\(command) was cancelled.",
      symbolName: "minus.circle.fill",
      accessibilityLabel: "Command cancelled",
      severity: .cancelled)
  }
}

enum TerminalTabStatusSeverity {
  case warning
  case error
  case cancelled
}

extension ExitCodeSeverity {
  var terminalSeverity: TerminalTabStatusSeverity {
    switch self {
    case .warning:
      .warning
    case .error:
      .error
    }
  }
}
