import GUIForCLICore
import SwiftUI

struct TagPill: View {
  let tag: TagSpec
  var uppercased: Bool = true

  var body: some View {
    Text(tag.title)
      .font(.caption2.weight(.semibold))
      .textCase(uppercased ? .uppercase : nil)
      .foregroundStyle(foregroundStyle)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(backgroundStyle, in: Capsule())
      .overlay {
        Capsule()
          .stroke(foregroundStyle.opacity(0.45), lineWidth: 0.75)
      }
  }

  private var foregroundStyle: Color {
    switch tag.style {
    case .primary:
      return .accentColor
    case .secondary:
      return .secondary
    case .success:
      return .green
    case .warning:
      return .orange
    case .danger:
      return .red
    }
  }

  private var backgroundStyle: Color {
    foregroundStyle.opacity(0.24)
  }
}
