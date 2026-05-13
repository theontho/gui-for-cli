import GUIForCLICore
import SwiftUI

struct IconTitleLabel: View {
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.bundleIconSet) private var iconSet
  @Environment(\.bundleIconMap) private var iconMap
  let title: String
  let iconName: String?
  let textIcon: String?
  let defaultSystemImage: String
  var iconOnly = false
  var fixedIconWidth: CGFloat? = nil

  var body: some View {
    if iconSet == .emoji {
      HStack(spacing: iconOnly ? 0 : 6) {
        sizedIcon(Text(resolvedTextIcon))
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

  private var resolvedTextIcon: String {
    textIcon.nonEmpty
      ?? iconMap.resolving(iconName, source: BundleIconMap.emojiSource)
      ?? "•"
  }

  private var systemImageName: String {
    iconMap.resolving(
      iconName.nonEmpty ?? defaultSystemImage,
      source: BundleIconMap.sfSymbolsSource,
      fallbackToKey: false) ?? defaultSystemImage
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

private struct BundleIconSetKey: EnvironmentKey {
  static let defaultValue: BundleIconSet = .platform
}

private struct BundleIconMapKey: EnvironmentKey {
  static let defaultValue = BuiltinIconMap.load()
}

extension EnvironmentValues {
  var bundleIconSet: BundleIconSet {
    get { self[BundleIconSetKey.self] }
    set { self[BundleIconSetKey.self] = newValue }
  }

  var bundleIconMap: BundleIconMap {
    get { self[BundleIconMapKey.self] }
    set { self[BundleIconMapKey.self] = newValue }
  }
}
