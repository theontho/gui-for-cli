import Foundation
import GUIForCLICore
import SwiftUI

struct ActionButton: View {
  @Environment(\.commandRenderContext) private var context
  @Environment(\.bundleLocalizationLabels) private var localizationLabels
  @EnvironmentObject private var terminal: TerminalLogStore
  let action: ActionSpec
  var reserveEstimateSpace = false
  var run: () -> Void
  @State private var isConfirming = false
  @State private var confirmationInput = ""

  var body: some View {
    let missingPlaceholders = action.command.missingPlaceholders(resolving: context)
    let displayCommand = action.command.displayCommand(resolving: context)
    let isRunning = terminal.isCommandRunning(displayCommand)
    let disabledReason = action.disabledReason(resolving: context)
    let precheckResult = action.precheck.flatMap {
      ActionPrecheckEvaluator.evaluate(
        spec: $0, context: context, labels: localizationLabels)
    }
    let isActionDisabled =
      !missingPlaceholders.isEmpty || disabledReason != nil || isRunning
      || precheckResult?.severity == .warning || isUnsupportedPlatform
    let help = helpText(missingPlaceholders: missingPlaceholders, disabledReason: disabledReason)

    VStack(alignment: .leading, spacing: 6) {
      if let precheckResult {
        ActionPrecheckBanner(
          severity: precheckResult.severity,
          title: precheckResult.title,
          message: precheckResult.message)
      }
      Button(role: action.role == .destructive ? .destructive : nil) {
        if action.confirm != nil {
          confirmationInput = ""
          isConfirming = true
        } else {
          run()
        }
      } label: {
        if isRunning {
          HStack {
            ProgressView()
              .controlSize(.small)
            if !action.iconOnly {
              Text(action.title)
            }
          }
          .frame(maxWidth: action.iconOnly ? nil : .infinity)
        } else {
          IconTitleLabel(
            title: action.title,
            iconName: action.iconName,
            textIcon: action.textIcon,
            defaultSystemImage: "play",
            iconOnly: action.iconOnly
          )
          .frame(maxWidth: action.iconOnly ? nil : .infinity)
        }
      }
      .controlSize(.regular)
      .disabled(isActionDisabled)
      .destructiveActionStyle(
        isDestructive: action.role == .destructive, isDisabled: isActionDisabled
      )
      .quickHelp(precheckResult?.severity == .warning ? (precheckResult?.message ?? help) : help)
      .axAction(action, isDisabled: isActionDisabled)
      .sheet(isPresented: $isConfirming) {
        if let confirmation = action.confirm {
          ActionConfirmationSheet(
            action: action,
            confirmation: confirmation,
            context: context,
            input: $confirmationInput,
            isPresented: $isConfirming,
            confirm: run)
        }
      }
      if let estimate = action.estimatedDurationLabel {
        estimateView(estimate)
      } else if reserveEstimateSpace {
        estimateView("0:00")
          .hidden()
          .accessibilityHidden(true)
      }
    }
  }

  private func estimateView(_ estimate: String) -> some View {
    HStack(spacing: 4) {
      Image(systemName: "clock")
      Text(estimate)
    }
    .font(.caption2.monospacedDigit())
    .foregroundStyle(.secondary)
    .accessibilityLabel("Estimated time \(estimate)")
  }

  private func helpText(missingPlaceholders: [String], disabledReason: String?) -> String {
    if !missingPlaceholders.isEmpty {
      let missing = missingPlaceholders.map { placeholder in
        context.label(for: placeholder) ?? Self.placeholderLabel(placeholder)
      }.joined(separator: ", ")
      if let tooltip = action.tooltip?.nonEmpty {
        return "\(tooltip)\n\nMissing: \(missing)"
      }
      return "Missing: \(missing)"
    }
    if let disabledReason {
      if let tooltip = action.tooltip?.nonEmpty {
        return "\(tooltip)\n\n\(disabledReason)"
      }
      return disabledReason
    }
    if isUnsupportedPlatform {
      return "Running commands is only supported on macOS."
    }
    return action.tooltip ?? action.command.displayCommand(resolving: context)
  }

  private static func placeholderLabel(_ placeholder: String) -> String {
    let trimmed =
      placeholder
      .replacingOccurrences(of: "row.", with: "")
      .replacingOccurrences(of: "config.", with: "")
    return
      trimmed
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
  }

  private var isUnsupportedPlatform: Bool {
    #if os(macOS)
      return false
    #else
      return true
    #endif
  }
}

extension ActionSpec {
  var estimatedDurationLabel: String? {
    guard let minutes = estimatedDurationMinutes, minutes >= 0 else { return nil }
    return "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
  }
}
