import GUIForCLICore
import SwiftUI

@main
struct GUIForCLIiOSApp: App {
  @StateObject private var textScale = AppTextScale()
  @State private var importedBundleURL: URL? = nil

  var body: some Scene {
    WindowGroup {
      iOSRootView(importedBundleURL: $importedBundleURL)
        .dynamicTypeSize(textScale.dynamicTypeSize)
    }
  }
}

private struct iOSRootView: View {
  @Binding var importedBundleURL: URL?
  @State private var isChangingBundle = false

  private var activeBundleURL: URL? {
    importedBundleURL ?? DemoBundle.wgsExtractResourceRootURLIfAvailable
  }

  var body: some View {
    Group {
      if let url = activeBundleURL {
        ContentView(platformName: "iOS", bundleRootURL: url)
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
              Button {
                isChangingBundle = true
              } label: {
                Label("Open Bundle", systemImage: "folder.badge.plus")
              }
            }
          }
      } else {
        BundleWelcomeView { url in
          importedBundleURL = url
        }
      }
    }
    .sheet(isPresented: $isChangingBundle) {
      BundleWelcomeView { url in
        importedBundleURL = url
        isChangingBundle = false
      }
    }
  }
}
