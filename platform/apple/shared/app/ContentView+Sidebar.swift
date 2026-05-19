import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

extension ContentView {
  static let sidebarWidth: CGFloat = 220
  static let minimumSidebarWidth: CGFloat = 160
  static let maximumSidebarWidth: CGFloat = 420
  static let minimumDetailWidth: CGFloat = 520
  static let sidebarIconWidth: CGFloat = 22

  func sidebarContent(opaqueBackground: Bool) -> some View {
    VStack(spacing: 0) {
      BundleHeader(manifest: manifest, rootURL: bundleRootURL)
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, 10)

      List(selection: $selectedPageID) {
        ForEach(primarySidebarGroups) { group in
          if let title = group.title {
            Section(title) {
              ForEach(group.pages) { page in
                sidebarPageLabel(for: page)
              }
            }
          } else {
            ForEach(group.pages) { page in
              sidebarPageLabel(for: page)
            }
          }
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(opaqueBackground ? .hidden : .automatic)
      .background(sidebarBackgroundColor(opaque: opaqueBackground))

      if !bottomSidebarPages.isEmpty {
        Divider()

        List(selection: $selectedPageID) {
          ForEach(bottomSidebarPages) { page in
            sidebarPageLabel(for: page)
          }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(opaqueBackground ? .hidden : .automatic)
        .background(sidebarBackgroundColor(opaque: opaqueBackground))
        .frame(height: CGFloat(bottomSidebarPages.count) * 44 + 8)
      }
    }
    .background(sidebarBackgroundColor(opaque: opaqueBackground))
  }

  func persistSelectedPageID(_ pageID: String?) {
    guard let pageID, manifest.pages.contains(where: { $0.id == pageID }) else { return }
    configStore.bundleState.selectedPageID = pageID
    configStore.persistBundleState()
  }

  func sidebarBackgroundColor(opaque: Bool) -> Color {
    guard opaque else { return Color.clear }
    #if os(macOS)
      return Color(nsColor: .windowBackgroundColor)
    #else
      return Color(uiColor: .systemBackground)
    #endif
  }

  #if os(macOS)
    static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
      min(max(width, minimumSidebarWidth), maximumSidebarWidth)
    }
  #endif

  var primarySidebarPages: [BundlePage] {
    manifest.pages.filter { $0.sidebarPlacement != .bottom }
  }

  var primarySidebarGroups: [SidebarPageGroup] {
    SidebarPageGroup.groups(for: primarySidebarPages)
  }

  var bottomSidebarPages: [BundlePage] {
    manifest.pages.filter { $0.sidebarPlacement == .bottom }
  }

  func sidebarPageLabel(for page: BundlePage) -> some View {
    IconTitleLabel(
      title: page.title,
      iconName: page.iconName,
      textIcon: page.textIcon,
      defaultSystemImage: "doc.text",
      fixedIconWidth: Self.sidebarIconWidth
    )
    .tag(page.id)
  }
}
