import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#endif

struct BundleBootstrapView: View {
  let platformName: String
  let initialBundleRootURL: URL
  let fallbackManifest: CLIBundleManifest?
  let onSessionLoaded: @MainActor (BundleSession) -> Void

  @State private var active: ActiveBundleSession?
  @State private var isLoading = false
  @State private var loadingErrorMessage = ""
  @State private var isLoadingErrorPresented = false

  init(
    platformName: String,
    bundleRootURL: URL = DemoBundle.defaultResourceRootURL,
    fallbackManifest: CLIBundleManifest? = nil,
    onSessionLoaded: @escaping @MainActor (BundleSession) -> Void = { _ in }
  ) {
    self.platformName = platformName
    self.initialBundleRootURL = bundleRootURL
    self.fallbackManifest = fallbackManifest
    self.onSessionLoaded = onSessionLoaded
  }

  var body: some View {
    Group {
      if let active {
        ContentView(platformName: platformName, active: active)
          .id(active.id)
      } else {
        loadingContent
      }
    }
    .overlay {
      if isLoading, active != nil {
        ProgressView()
          .controlSize(.large)
          .padding(24)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
      }
    }
    .task {
      guard active == nil else { return }
      await loadSession(from: initialBundleRootURL)
    }
    .focusedSceneValue(
      \.loadBundle,
      LoadBundleAction { url in
        Task { await loadSession(from: url) }
      }
    )
    #if os(macOS)
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification))
      {
        _ in
        active?.tearDown()
      }
    #endif
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
      Text("Preparing the bundle workspace.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(minWidth: 640, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
    .background(.background)
  }

  /// Loads a bundle while the current one stays on screen, then tears the
  /// current one down (pending writes, running process trees) and swaps.
  @MainActor
  private func loadSession(from sourceRootURL: URL) async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      install(try await bootstrap(sourceRootURL), from: sourceRootURL)
    } catch {
      loadingErrorMessage = error.localizedDescription
      isLoadingErrorPresented = true
      // Without any bundle on screen, fall back to the initial bundle.
      guard active == nil, sourceRootURL != initialBundleRootURL,
        let session = try? await bootstrap(initialBundleRootURL)
      else { return }
      install(session, from: initialBundleRootURL)
    }
  }

  private func bootstrap(_ sourceRootURL: URL) async throws -> BundleSession {
    let fallbackManifest = fallbackManifest
    return try await Task.detached(priority: .userInitiated) {
      let loadedBundle = try BundleSourceLoader().load(from: sourceRootURL)
      return BundleSessionLoader.bootstrap(
        sourceRootURL: sourceRootURL,
        fallbackManifest: fallbackManifest ?? loadedBundle.manifest,
        systemPreferences: BundleSessionLoader.systemPreferredLocalizations())
    }.value
  }

  private func install(_ session: BundleSession, from sourceRootURL: URL) {
    active?.tearDown()
    active = ActiveBundleSession(session: session, sourceRootURL: sourceRootURL)
    onSessionLoaded(session)
  }
}

/// Loads a bundle into the window that published it (scene-scoped, so the
/// Load Bundle command only affects the focused window).
struct LoadBundleAction {
  let load: @MainActor (URL) -> Void

  @MainActor func callAsFunction(_ url: URL) {
    load(url)
  }
}

private struct LoadBundleActionKey: FocusedValueKey {
  typealias Value = LoadBundleAction
}

extension FocusedValues {
  var loadBundle: LoadBundleAction? {
    get { self[LoadBundleActionKey.self] }
    set { self[LoadBundleActionKey.self] = newValue }
  }
}
