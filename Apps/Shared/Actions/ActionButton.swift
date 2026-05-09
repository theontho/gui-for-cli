import GUIForCLICore

import SwiftUI

#if !os(macOS)
  import UIKit
#endif
struct ActionButton: View {
  @Environment(\.commandRenderContext) private var context
  @Environment(\.bundleLocalizationLabels) private var localizationLabels
  @EnvironmentObject private var terminal: TerminalLogStore
  let action: ActionSpec
  var run: () -> Void
  @State private var isConfirming = false
  @State private var confirmationInput = ""
  #if !os(macOS)
    @State private var isCopied = false
  #endif

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
      || precheckResult?.severity == .warning
    let help = helpText(missingPlaceholders: missingPlaceholders, disabledReason: disabledReason)

    VStack(alignment: .leading, spacing: 6) {
      if let precheckResult {
        ActionPrecheckBanner(
          severity: precheckResult.severity,
          title: precheckResult.title,
          message: precheckResult.message)
      }
      Button(role: action.role == .destructive ? .destructive : nil) {
        #if os(macOS)
          if action.confirm != nil {
            confirmationInput = ""
            isConfirming = true
          } else {
            run()
          }
        #else
          copyCommandToClipboard()
        #endif
      } label: {
        #if os(macOS)
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
              iconEmoji: action.iconEmoji,
              defaultSystemImage: "play",
              iconOnly: action.iconOnly
            )
            .frame(maxWidth: action.iconOnly ? nil : .infinity)
          }
        #else
          IconTitleLabel(
            title: isCopied ? "Copied!" : action.title,
            iconName: isCopied ? nil : action.iconName,
            iconEmoji: isCopied ? nil : action.iconEmoji,
            defaultSystemImage: isCopied ? "checkmark" : "doc.on.clipboard",
            iconOnly: action.iconOnly
          )
          .frame(maxWidth: action.iconOnly ? nil : .infinity)
        #endif
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
    }
  }

  private func helpText(missingPlaceholders: [String], disabledReason: String?) -> String {
    if !missingPlaceholders.isEmpty {
      let missing = missingPlaceholders.map(Self.placeholderLabel).joined(separator: ", ")
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
    #if os(macOS)
      return action.tooltip ?? action.command.displayCommand(resolving: context)
    #else
      return action.tooltip ?? "Tap to copy command to clipboard."
    #endif
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

  #if !os(macOS)
    private func copyCommandToClipboard() {
      let command = action.command.renderedCommand(resolving: context)
      UIPasteboard.general.string = command.displayCommand
      isCopied = true
      Task {
        try? await Task.sleep(for: .seconds(2))
        isCopied = false
      }
    }
  #endif
}
