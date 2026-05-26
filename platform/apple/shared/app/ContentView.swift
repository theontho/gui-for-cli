import Foundation
import GUIForCLICore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct ContentView: View {
  // MARK: - State

  let platformName: String
  let bundleSourceRootURL: URL?

  @State var manifest: CLIBundleManifest
  @State var selectedPageID: String?
  @State var selectedLocalizationCode: String
  @State var usingSystemDefaultLocale: Bool
  @State var localizationOptions: [BundleLocalizationOption]
  @State var localizationLabels: BundleLocalizationLabels
  @State var iconMap: BundleIconMap
  @State var selectedIconSet: BundleIconSet
  @State var selectedColorTheme: BundleColorTheme
  @State var bundleRootURL: URL?
  @State var startupMessages: [String]
  @State var isTerminalVisible = true
  @State var isSetupRunning = false
  @State var runningSetupStepID: String?
  @State var liveSetupRun: BundleSetupRunState?
  @State var isSetupPromptPresented = false
  @State var hasPresentedSetupPrompt = false
  @State var isRTLSidebarVisible: Bool
  @State var rtlSidebarWidth: CGFloat
  @State var rtlSidebarDragStartWidth: CGFloat?
  @StateObject var terminal: TerminalLogStore
  @StateObject var configStore: BundleConfigStore

  init(
    platformName: String,
    manifest: CLIBundleManifest? = nil,
    bundleRootURL: URL? = nil
  ) {
    let contentInitStart = Date()
    let sourceBundleRootURL = bundleRootURL ?? DemoBundle.wgsExtractResourceRootURL
    let session = BundleSessionLoader.bootstrap(
      sourceRootURL: sourceBundleRootURL,
      fallbackManifest: manifest ?? DemoBundle.wgsExtract,
      systemPreferences: BundleSessionLoader.systemPreferredLocalizations())
    self.init(
      platformName: platformName,
      bundleSourceRootURL: sourceBundleRootURL,
      session: session,
      contentInitStart: contentInitStart)
  }

  init(
    platformName: String,
    bundleSourceRootURL: URL?,
    session: BundleSession,
    contentInitStart: Date = Date()
  ) {
    self.platformName = platformName
    self.bundleSourceRootURL = bundleSourceRootURL

    _manifest = State(initialValue: session.manifest)
    _selectedPageID = State(initialValue: Self.initialSelectedPageID(for: session))
    _selectedLocalizationCode = State(initialValue: session.localizationCode)
    _usingSystemDefaultLocale = State(initialValue: session.usingSystemDefaultLocale)
    _localizationOptions = State(initialValue: session.localizationOptions)
    _localizationLabels = State(initialValue: session.localizationLabels)
    _iconMap = State(initialValue: session.iconMap)
    _selectedIconSet = State(initialValue: session.bundleState.iconSet)
    _selectedColorTheme = State(initialValue: session.bundleState.colorTheme)
    _bundleRootURL = State(initialValue: session.bundleRootURL)
    _startupMessages = State(initialValue: session.startupMessages)
    _isSetupRunning = State(initialValue: false)
    _runningSetupStepID = State(initialValue: nil)
    _liveSetupRun = State(initialValue: nil)
    _isSetupPromptPresented = State(initialValue: false)
    _hasPresentedSetupPrompt = State(initialValue: false)
    _isRTLSidebarVisible = State(initialValue: true)
    _rtlSidebarWidth = State(initialValue: Self.sidebarWidth)
    _rtlSidebarDragStartWidth = State(initialValue: nil)
    let terminalStore = TerminalLogStore(
      exitCodeReference: session.manifest.effectiveExitCodeReference,
      localizationLabels: session.localizationLabels)
    _terminal = StateObject(wrappedValue: terminalStore)
    _configStore = StateObject(
      wrappedValue: BundleConfigStore(
        session: session,
        log: { [weak terminalStore] message in terminalStore?.appendToMain(message) }))
    StartupBenchmark.markContentInitialized(since: contentInitStart)
  }

  // MARK: - Body

  var body: some View {
    rootContent
      .environment(\.bundleIconSet, selectedIconSet)
      .environment(\.bundleIconMap, iconMap)
      .preferredColorScheme(selectedColorTheme.swiftUIColorScheme)
      .environmentObject(terminal)
      .environmentObject(configStore)
      .onAppear {
        if let bundleSourceRootURL, BundleHotReloader.isEnabled {
          BundleHotReloader.shared.start(at: bundleSourceRootURL)
        }
        presentSetupPromptIfNeeded()
      }
      .alert(localizationLabels.setupTitle, isPresented: $isSetupPromptPresented) {
        Button(localizationLabels.setupRunButtonTitle) {
          goToSetupAndStart()
        }
        .disabled(setupPreflightResult?.severity == .warning)
        Button(localizationLabels.terminalCancelButtonTitle, role: .cancel) {}
      } message: {
        Text(setupPromptMessage)
      }
      .onChange(of: manifest) { _, newValue in
        configStore.manifest = newValue
        presentSetupPromptIfNeeded()
      }
      .onChange(of: selectedPageID) { _, newValue in
        persistSelectedPageID(newValue)
      }
      .onReceive(BundleHotReloader.shared.changes) { _ in
        guard BundleHotReloader.isEnabled else { return }
        applyLocalization(selectedLocalizationCode, persist: false)
        terminal.appendToMain("[hot-reload] bundle sources changed; manifest reloaded")
      }
      .onReceive(
        NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
      ) { _ in
        systemLocaleDidChange()
      }
  }

  private static func initialSelectedPageID(for session: BundleSession) -> String? {
    if let selectedPageID = session.bundleState.selectedPageID,
      session.manifest.pages.contains(where: { $0.id == selectedPageID })
    {
      return selectedPageID
    }
    return session.manifest.pages.first?.id
  }

}

#Preview {
  ContentView(platformName: "Preview")
}
