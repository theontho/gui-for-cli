import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct PageRenderer: View {
  @EnvironmentObject private var configStore: BundleConfigStore
  let page: BundlePage
  let localizationLabels: BundleLocalizationLabels
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
  var headerAccessory: AnyView?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          IconTitleLabel(
            title: page.title,
            iconName: page.iconName,
            iconEmoji: page.iconEmoji,
            defaultSystemImage: "doc.text"
          )
          .font(.largeTitle.weight(.semibold))
          .axHeading(.h1)
          Text(page.summary)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .help(page.summary)
        }

        if let headerAccessory {
          headerAccessory
        }

        ForEach(page.sections) { section in
          SectionRenderer(
            section: section,
            localizationLabels: localizationLabels,
            bundleRootURL: bundleRootURL,
            runAction: runAction
          )
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(.background)
    .axPage(page)
  }
}
