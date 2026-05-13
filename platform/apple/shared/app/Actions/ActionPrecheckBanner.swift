import GUIForCLICore
import SwiftUI

struct ActionPrecheckBanner: View {
  let severity: ActionPrecheckResult.Severity
  let title: String
  let message: String

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: iconName)
        .foregroundStyle(accentColor)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.semibold))
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(accentColor.opacity(0.12))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(accentColor.opacity(0.45), lineWidth: 0.5)
    )
  }

  private var iconName: String {
    switch severity {
    case .info: "internaldrive"
    case .warning: "exclamationmark.triangle.fill"
    }
  }

  private var accentColor: Color {
    switch severity {
    case .info: .accentColor
    case .warning: .orange
    }
  }
}
