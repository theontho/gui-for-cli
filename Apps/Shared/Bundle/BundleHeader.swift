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
