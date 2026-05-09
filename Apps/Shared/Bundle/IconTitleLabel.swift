import GUIForCLICore
import SwiftUI

struct IconTitleLabel: View {
  @Environment(\.layoutDirection) private var layoutDirection
  let title: String
  let iconName: String?
  let iconEmoji: String?
  let defaultSystemImage: String
  var iconOnly = false
  var fixedIconWidth: CGFloat? = nil

  var body: some View {
    if let iconEmoji, !iconEmoji.isEmpty {
      HStack(spacing: iconOnly ? 0 : 6) {
        sizedIcon(Text(iconEmoji))
        if !iconOnly {
          Text(title)
        }
      }
      .accessibilityLabel(title)
    } else {
      if iconOnly {
        sizedIcon(systemImage)
          .accessibilityLabel(title)
      } else {
        HStack(spacing: 6) {
          sizedIcon(systemImage)
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

  @ViewBuilder
  private func sizedIcon<Content: View>(_ content: Content) -> some View {
    if let fixedIconWidth {
      content.frame(width: fixedIconWidth, alignment: .center)
    } else {
      content
    }
  }

  private var shouldMirrorSystemImage: Bool {
    layoutDirection == .rightToLeft && systemImageName == "play"
  }
}
