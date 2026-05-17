import GUIForCLICore
import SwiftUI

struct BundleBootstrapView: View {
  let platformName: String
  let bundleRootURL: URL
  let fallbackManifest: CLIBundleManifest?

  @State private var session: BundleSession?

  init(
    platformName: String,
    bundleRootURL: URL = DemoBundle.defaultResourceRootURL,
    fallbackManifest: CLIBundleManifest? = nil
  ) {
    self.platformName = platformName
    self.bundleRootURL = bundleRootURL
    self.fallbackManifest = fallbackManifest
  }

  var body: some View {
    Group {
      if let session {
        ContentView(
          platformName: platformName,
          bundleSourceRootURL: bundleRootURL,
          session: session)
      } else {
        loadingContent
      }
    }
    .task {
      await loadSessionIfNeeded()
    }
  }

  private var loadingContent: some View {
    VStack(spacing: 12) {
      ProgressView()
        .controlSize(.large)
      Text("Loading GUI for CLI...")
        .font(.headline)
      Text("Preparing the sample bundle workspace.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(minWidth: 640, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
    .background(.background)
  }

  @MainActor
  private func loadSessionIfNeeded() async {
    guard session == nil else { return }
    let bundleRootURL = bundleRootURL
    let fallbackManifest = fallbackManifest
    session = await Task.detached(priority: .userInitiated) {
      BundleSessionLoader.bootstrap(
        sourceRootURL: bundleRootURL,
        fallbackManifest: fallbackManifest ?? DemoBundle.defaultManifest,
        systemPreferences: BundleSessionLoader.systemPreferredLocalizations())
    }.value
  }
}
