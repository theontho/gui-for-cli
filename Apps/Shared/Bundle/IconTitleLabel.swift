import GUIForCLICore
import SwiftUI

struct IconTitleLabel: View {
  @Environment(\.layoutDirection) private var layoutDirection
  let title: String
  let iconName: String?
  let iconEmoji: String?
  let defaultSystemImage: String
  var iconOnly = false

  var body: some View {
    if let iconEmoji, !iconEmoji.isEmpty {
      HStack(spacing: iconOnly ? 0 : 6) {
        Text(iconEmoji)
        if !iconOnly {
          Text(title)
        }
      }
      .accessibilityLabel(title)
    } else {
      if iconOnly {
        systemImage
          .accessibilityLabel(title)
      } else {
        HStack(spacing: 6) {
          systemImage
          Text(title)
        }
        .accessibilityLabel(title)
      }
    }
  }

  private var systemImageName: String {
    iconName.nonEmpty ?? defaultSystemImage
  }

  private var systemImage: some View {
    Image(systemName: systemImageName)
      .scaleEffect(x: shouldMirrorSystemImage ? -1 : 1, y: 1)
  }

  private var shouldMirrorSystemImage: Bool {
    layoutDirection == .rightToLeft && systemImageName == "play"
  }
}
