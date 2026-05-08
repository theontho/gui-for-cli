import GUIForCLICore
import SwiftUI

struct BundleHeader: View {
  let manifest: CLIBundleManifest
  let rootURL: URL?

  var body: some View {
    VStack(spacing: 10) {
      if manifest.sidebarIconStyle != .hidden {
        BundleIconView(manifest: manifest, rootURL: rootURL, size: 72)
      }

      HStack(spacing: 6) {
        InfoLabel(
          text: manifest.displayName,
          tooltip: manifest.summary,
          font: .headline.weight(.semibold)
        )
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, alignment: .center)
    }
  }
}

struct BundleIconView: View {
  let manifest: CLIBundleManifest
  let rootURL: URL?
  var size: CGFloat = 34

  var body: some View {
    iconContent
      .frame(width: size, height: size)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.22))
  }

  @ViewBuilder private var iconContent: some View {
    switch manifest.sidebarIconStyle {
    case .automatic:
      if let image = bundleImage {
        imageIcon(image)
      } else if let emoji = nonEmptyEmoji {
        emojiIcon(emoji)
      } else {
        symbolIcon
      }
    case .image:
      if let image = bundleImage {
        imageIcon(image)
      } else {
        symbolIcon
      }
    case .emoji:
      if let emoji = nonEmptyEmoji {
        emojiIcon(emoji)
      } else {
        symbolIcon
      }
    case .symbol, .hidden:
      symbolIcon
    }
  }

  private func imageIcon(_ image: Image) -> some View {
    image
      .resizable()
      .scaledToFit()
  }

  private func emojiIcon(_ emoji: String) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        .fill(
          LinearGradient(
            colors: [.accentColor.opacity(0.85), .accentColor.opacity(0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
        )
      Text(emoji)
        .font(.system(size: size * 0.54))
    }
  }

  private var symbolIcon: some View {
    Image(systemName: manifest.iconName)
      .resizable()
      .scaledToFit()
      .foregroundStyle(.tint)
      .padding(size * 0.2)
  }

  private var bundleImage: Image? {
    guard let rootURL, let iconPath = manifest.iconPath, !iconPath.isEmpty else {
      return nil
    }
    let url = rootURL.appendingPathComponent(iconPath, isDirectory: false)
    #if os(macOS)
      guard let image = NSImage(contentsOf: url) else { return nil }
      return Image(nsImage: image)
    #else
      guard let image = UIImage(contentsOfFile: url.path) else { return nil }
      return Image(uiImage: image)
    #endif
  }

  private var nonEmptyEmoji: String? {
    guard let emoji = manifest.iconEmoji, !emoji.isEmpty else {
      return nil
    }
    return emoji
  }
}

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
