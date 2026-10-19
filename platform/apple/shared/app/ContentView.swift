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
  let terminal: TerminalLogStore
  let configStore: BundleConfigStore

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
  @State var isTerminalVisible = true
  @State var isSetupRunning = false
  @State var runningSetupStepID: String?
  @State var runningSetupStepStartedAt: Date?
  @State var liveSetupRun: BundleSetupRunState?
  @State var hasStartedAutomatedSetup = false
  @State var isSetupPromptPresented = false
  @State var hasPresentedSetupPrompt = false
  @State var isRTLSidebarVisible = true
  @State var rtlSidebarWidth: CGFloat = ContentView.sidebarWidth
  @State var rtlSidebarDragStartWidth: CGFloat?

  init(platformName: String, active: ActiveBundleSession, contentInitStart: Date = Date()) {
    let session = active.session
    self.platformName = platformName
    bundleSourceRootURL = active.sourceRootURL
    terminal = active.terminal
    configStore = active.configStore
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
    StartupBenchmark.markContentInitialized(since: contentInitStart)
  }

  /// Language for app chrome strings; follows the bundle's language picker.
  var chromeLocale: Locale {
    Locale(identifier: selectedLocalizationCode)
  }

  // MARK: - Body

  var body: some View {
    rootContent
      .environment(\.bundleIconSet, selectedIconSet)
      .environment(\.bundleIconMap, iconMap)
      .preferredColorScheme(selectedColorTheme.swiftUIColorScheme)
      .environment(\.locale, chromeLocale)
      .environment(terminal)
      .environment(configStore)
      .onAppear {
        if let bundleSourceRootURL, BundleHotReloader.isEnabled {
          BundleHotReloader.shared.start(at: bundleSourceRootURL)
        }
        if Self.autoRunsSetup {
          startAutomatedSetupIfNeeded()
        } else {
          presentSetupPromptIfNeeded()
        }
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
      .onChange(of: localizationLabels) { _, newValue in
        terminal.updateLocalization(newValue, locale: chromeLocale)
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
  BundleBootstrapView(platformName: "Preview")
}
