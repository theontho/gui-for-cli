import GUIForCLICore
import SwiftUI

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
    reference: ExitCodeReferenceEntry?,
    labels: BundleLocalizationLabels,
    locale: Locale
  ) -> TerminalTabStatus {
    let resolvedSeverity = reference?.severity.terminalSeverity ?? severity
    let code = Int(exitCode)
    let values = ["code": String(code), "command": command]
    return TerminalTabStatus(
      title: reference?.title
        ?? BundleLocalizationLabels.fill(labels.terminalExitCodeTitleFormat, values),
      blurb: reference?.summary ?? labels.terminalNonzeroExitSummary,
      detail: BundleLocalizationLabels.fill(labels.terminalExitDetailFormat, values),
      symbolName: resolvedSeverity.symbolName,
      accessibilityLabel: String(chrome: "Command exited with code \(code)", locale: locale),
      severity: resolvedSeverity)
  }

  /// A death by signal. Signals never consult the bundle's exit-code reference.
  static func signaled(
    signal: Int32,
    command: String,
    severity: TerminalTabStatusSeverity,
    locale: Locale
  ) -> TerminalTabStatus {
    let name = ProcessTermination.signalName(signal)
    return TerminalTabStatus(
      title: String(chrome: "Terminated by \(name)", locale: locale),
      blurb: String(
        chrome: "The command was stopped by a signal before it finished.", locale: locale),
      detail: String(
        chrome: "\(command) was terminated by signal \(Int(signal)) (\(name)).", locale: locale),
      symbolName: severity.symbolName,
      accessibilityLabel: String(chrome: "Command terminated by \(name)", locale: locale),
      severity: severity)
  }

  static func processError(
    command: String,
    message: String,
    severity: TerminalTabStatusSeverity = .error,
    labels: BundleLocalizationLabels,
    locale: Locale
  ) -> TerminalTabStatus {
    let title =
      severity == .warning
      ? String(chrome: "Command warning", locale: locale) : labels.terminalProcessErrorTitle
    return TerminalTabStatus(
      title: title,
      blurb: labels.terminalProcessErrorSummary,
      detail: "\(command)\n\(message)",
      symbolName: severity.symbolName,
      accessibilityLabel: title,
      severity: severity)
  }

  static func cancelled(
    command: String, reference: ExitCodeReferenceEntry?, locale: Locale
  ) -> TerminalTabStatus {
    TerminalTabStatus(
      title: reference?.title ?? String(chrome: "Command cancelled", locale: locale),
      blurb: reference?.summary
        ?? String(
          chrome:
            "The command was cancelled before it finished. Partial output may have been produced.",
          locale: locale),
      detail: String(chrome: "\(command) was cancelled.", locale: locale),
      symbolName: "minus.circle.fill",
      accessibilityLabel: String(chrome: "Command cancelled", locale: locale),
      severity: .cancelled)
  }
}

enum TerminalTabStatusSeverity {
  case warning
  case error
  case cancelled

  var symbolName: String {
    switch self {
    case .warning: "exclamationmark.triangle.fill"
    case .error: "xmark.octagon.fill"
    case .cancelled: "minus.circle.fill"
    }
  }
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
