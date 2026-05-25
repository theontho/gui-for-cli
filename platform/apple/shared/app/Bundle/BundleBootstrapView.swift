import GUIForCLICore
import SwiftUI

struct BundleBootstrapView: View {
  let platformName: String
  let initialBundleRootURL: URL
  let fallbackManifest: CLIBundleManifest?

  @State private var sourceRootURL: URL
  @State private var session: BundleSession?
  @State private var contentID = UUID()
  @State private var isLoading = false
  @State private var loadingErrorMessage = ""
  @State private var isLoadingErrorPresented = false

  init(
    platformName: String,
    bundleRootURL: URL = DemoBundle.defaultResourceRootURL,
    fallbackManifest: CLIBundleManifest? = nil
  ) {
    self.platformName = platformName
    self.initialBundleRootURL = bundleRootURL
    self.fallbackManifest = fallbackManifest
    _sourceRootURL = State(initialValue: bundleRootURL)
  }

  var body: some View {
    Group {
      if let session {
        ContentView(
          platformName: platformName,
          bundleSourceRootURL: sourceRootURL,
          session: session
        )
        .id(contentID)
      } else {
        loadingContent
      }
    }
    .task {
      await loadSessionIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: .guiForCLILoadBundle)) { notification in
      guard let url = notification.object as? URL else { return }
      Task {
        await loadSession(from: url)
      }
    }
    .alert("Could not load bundle", isPresented: $isLoadingErrorPresented) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(loadingErrorMessage)
    }
  }

  private var loadingContent: some View {
    VStack(spacing: 12) {
      ProgressView()
        .controlSize(.large)
      Text("Loading GUI for CLI...")
        .font(.headline)
      Text(
        isLoading
          ? "Preparing the selected bundle workspace." : "Preparing the sample bundle workspace."
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
    }
    .frame(minWidth: 640, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
    .background(.background)
  }

  @MainActor
  private func loadSessionIfNeeded() async {
    guard session == nil else { return }
    await loadSession(from: sourceRootURL)
  }

  @MainActor
  private func loadSession(from sourceRootURL: URL) async {
    guard !isLoading else { return }
    let fallbackManifest = fallbackManifest
    let previousSession = session
    let previousSourceRootURL = self.sourceRootURL
    let previousContentID = contentID
    isLoading = true
    session = nil
    do {
      let loadedSession = try await Task.detached(priority: .userInitiated) {
        let loadedBundle = try BundleSourceLoader().load(from: sourceRootURL)
        return BundleSessionLoader.bootstrap(
          sourceRootURL: sourceRootURL,
          fallbackManifest: fallbackManifest ?? loadedBundle.manifest,
          systemPreferences: BundleSessionLoader.systemPreferredLocalizations())
      }.value
      self.sourceRootURL = sourceRootURL
      session = loadedSession
      contentID = UUID()
    } catch {
      if let previousSession {
        self.sourceRootURL = previousSourceRootURL
        session = previousSession
        contentID = previousContentID
      } else if sourceRootURL != initialBundleRootURL {
        loadingErrorMessage = error.localizedDescription
        isLoadingErrorPresented = true
        do {
          session = try await Task.detached(priority: .userInitiated) {
            let loadedBundle = try BundleSourceLoader().load(from: initialBundleRootURL)
            return BundleSessionLoader.bootstrap(
              sourceRootURL: initialBundleRootURL,
              fallbackManifest: fallbackManifest ?? loadedBundle.manifest,
              systemPreferences: BundleSessionLoader.systemPreferredLocalizations())
          }.value
          self.sourceRootURL = initialBundleRootURL
          contentID = UUID()
          isLoading = false
          return
        } catch {
          isLoading = false
          return
        }
      }
      loadingErrorMessage = error.localizedDescription
      isLoadingErrorPresented = true
    }
    isLoading = false
  }
}

extension Notification.Name {
  static let guiForCLILoadBundle = Notification.Name("GUIForCLILoadBundle")
}
