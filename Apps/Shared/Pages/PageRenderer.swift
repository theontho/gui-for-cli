import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct PageRenderer: View {
  private static let immediateSectionCount = 2

  @EnvironmentObject private var configStore: BundleConfigStore
  let page: BundlePage
  let localizationLabels: BundleLocalizationLabels
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
  var headerAccessory: AnyView?
  @State private var isRenderingDeferredSections = false

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

        ForEach(visibleSections) { section in
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
    .task(id: page.id) {
      isRenderingDeferredSections = false
      try? await Task.sleep(nanoseconds: 150_000_000)
      isRenderingDeferredSections = true
    }
  }

  private var visibleSections: [PageSection] {
    guard !isRenderingDeferredSections, page.sections.count > Self.immediateSectionCount else {
      return page.sections
    }
    return Array(page.sections.prefix(Self.immediateSectionCount))
  }
}
