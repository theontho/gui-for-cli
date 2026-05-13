import GUIForCLICore
import SwiftUI

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
        textIcon: action.role == .destructive ? "⚠️" : action.textIcon,
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
