import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct ActionRow: View {
  let actions: [ActionSpec]
  let context: CommandRenderContext
  var runAction: (ActionSpec) -> Void

  var body: some View {
    let visibleActions = actions.filter { $0.isVisible(resolving: context) }
    if visibleActions.count == 1, let action = visibleActions.first {
      HStack {
        actionButton(action)
          .fixedSize(horizontal: true, vertical: false)
        Spacer(minLength: 0)
      }
    } else {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)], spacing: 10) {
        ForEach(visibleActions) { action in
          actionButton(action)
        }
      }
    }
  }

  private func actionButton(_ action: ActionSpec) -> some View {
    ActionButton(action: action) {
      runAction(action)
    }
    .environment(\.commandRenderContext, context)
  }
}

struct ActionButton: View {
  @Environment(\.commandRenderContext) private var context
  @Environment(\.bundleLocalizationLabels) private var localizationLabels
  @EnvironmentObject private var terminal: TerminalLogStore
  let action: ActionSpec
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
            iconEmoji: action.iconEmoji,
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
      .accessibilityLabel(action.title)
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
}

struct ActionConfirmationSheet: View {
  let action: ActionSpec
  let confirmation: ActionConfirmationSpec
  let context: CommandRenderContext
  @Binding var input: String
  @Binding var isPresented: Bool
  var confirm: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      IconTitleLabel(
        title: resolved(confirmation.title),
        iconName: action.role == .destructive ? "exclamationmark.triangle.fill" : action.iconName,
        iconEmoji: action.iconEmoji,
        defaultSystemImage: "questionmark.circle"
      )
      .font(.title3.weight(.semibold))

      if let message = confirmation.message?.nonEmpty {
        Text(resolved(message))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let requiredText = resolvedRequiredText {
        VStack(alignment: .leading, spacing: 6) {
          Text(resolved(confirmation.prompt ?? "Type \"\(requiredText)\" to confirm."))
            .font(.caption)
            .foregroundStyle(.secondary)
          TextField(requiredText, text: $input)
            .textFieldStyle(.roundedBorder)
        }
      }

      HStack {
        Spacer()
        Button(resolved(confirmation.cancelButtonTitle)) {
          isPresented = false
        }
        Button(
          resolved(confirmation.confirmButtonTitle),
          role: action.role == .destructive ? .destructive : nil
        ) {
          isPresented = false
          confirm()
        }
        .disabled(!canConfirm)
        .destructiveActionStyle(
          isDestructive: action.role == .destructive,
          isDisabled: !canConfirm
        )
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 420)
  }

  private var resolvedRequiredText: String? {
    resolved(confirmation.requiredText).nonEmpty
  }

  private var canConfirm: Bool {
    guard let requiredText = resolvedRequiredText else { return true }
    return input == requiredText
  }

  private func resolved(_ value: String?) -> String? {
    value.map { resolved($0) }
  }

  private func resolved(_ value: String) -> String {
    context.interpolated(value)
  }
}
