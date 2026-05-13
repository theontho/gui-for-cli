import GUIForCLICore
import SwiftUI

struct BundleIconView: View {
  @Environment(\.bundleIconSet) private var iconSet
  @Environment(\.bundleIconMap) private var iconMap
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
      if iconSet == .emoji {
        textIcon(preferredTextIcon)
      } else if let image = bundleImage {
        imageIcon(image)
      } else {
        symbolIcon
      }
    case .image:
      if iconSet == .emoji {
        textIcon(preferredTextIcon)
      } else if let image = bundleImage {
        imageIcon(image)
      } else {
        symbolIcon
      }
    case .emoji:
      textIcon(preferredTextIcon)
    case .symbol, .hidden:
      if iconSet == .emoji {
        textIcon(preferredTextIcon)
      } else {
        symbolIcon
      }
    }
  }

  private func imageIcon(_ image: Image) -> some View {
    image
      .resizable()
      .scaledToFit()
  }

  private func textIcon(_ textIcon: String) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        .fill(
          LinearGradient(
            colors: [.accentColor.opacity(0.85), .accentColor.opacity(0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
        )
      Text(textIcon)
        .font(.system(size: size * 0.54))
    }
  }

  private var symbolIcon: some View {
    Image(systemName: systemImageName)
      .resizable()
      .scaledToFit()
      .foregroundStyle(.tint)
      .padding(size * 0.2)
  }

  private var systemImageName: String {
    iconMap.resolving(
      manifest.iconName,
      source: BundleIconMap.sfSymbolsSource,
      fallbackToKey: false) ?? "app"
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

  private var preferredTextIcon: String {
    manifest.textIcon.nonEmpty
      ?? iconMap.resolving(manifest.iconName, source: BundleIconMap.emojiSource)
      ?? "•"
  }
}
