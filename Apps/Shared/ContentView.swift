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
  @State var selectedIconSet: BundleIconSet
  @State var selectedColorTheme: BundleColorTheme
  @State var bundleRootURL: URL?
  @State var startupMessages: [String]
  @State var isTerminalVisible = true
  @State var isSetupRunning = false
  @State var runningSetupStepID: String?
  @State var liveSetupRun: BundleSetupRunState?
  @State var hasAttemptedAutomaticSetup = false
  @State var rtlSidebarWidth: CGFloat
  @State var rtlSidebarDragStartWidth: CGFloat?
  @StateObject var terminal: TerminalLogStore
  @StateObject var configStore: BundleConfigStore

  init(
    platformName: String,
    manifest: CLIBundleManifest = DemoBundle.wgsExtract,
    bundleRootURL: URL? = DemoBundle.wgsExtractResourceRootURL
  ) {
    self.platformName = platformName
    let sourceBundleRootURL = bundleRootURL ?? DemoBundle.wgsExtractResourceRootURL
    self.bundleSourceRootURL = sourceBundleRootURL

    let session = BundleSessionLoader.bootstrap(
      sourceRootURL: sourceBundleRootURL,
      fallbackManifest: manifest,
      systemPreferences: BundleSessionLoader.systemPreferredLocalizations())

    _manifest = State(initialValue: session.manifest)
    _selectedPageID = State(initialValue: Self.initialSelectedPageID(for: session))
    _selectedLocalizationCode = State(initialValue: session.localizationCode)
    _usingSystemDefaultLocale = State(initialValue: session.usingSystemDefaultLocale)
    _localizationOptions = State(initialValue: session.localizationOptions)
    _localizationLabels = State(initialValue: session.localizationLabels)
    _selectedIconSet = State(initialValue: session.bundleState.iconSet)
    _selectedColorTheme = State(initialValue: session.bundleState.colorTheme)
    _bundleRootURL = State(initialValue: session.bundleRootURL)
    _startupMessages = State(initialValue: session.startupMessages)
    _isSetupRunning = State(initialValue: false)
    _runningSetupStepID = State(initialValue: nil)
    _liveSetupRun = State(initialValue: nil)
    _hasAttemptedAutomaticSetup = State(initialValue: false)
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
  }

  // MARK: - Body

  var body: some View {
    rootContent
      .environment(\.bundleIconSet, selectedIconSet)
      .preferredColorScheme(selectedColorTheme.swiftUIColorScheme)
      .environmentObject(terminal)
      .environmentObject(configStore)
      .onAppear {
        if let bundleSourceRootURL, BundleHotReloader.isEnabled {
          BundleHotReloader.shared.start(at: bundleSourceRootURL)
        }
        runInitialSetupIfNeeded()
      }
      .onChange(of: manifest) { _, newValue in
        configStore.manifest = newValue
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

  @ViewBuilder private var rootContent: some View {
    #if os(macOS)
      if localizationLabels.layoutDirection == .rightToLeft {
        rightSidebarContent
      } else {
        navigationSplitContent
      }
    #else
      navigationSplitContent
    #endif
  }

  private var navigationSplitContent: some View {
    NavigationSplitView {
      sidebarContent(opaqueBackground: false)
        .environment(\.layoutDirection, swiftUILayoutDirection)
        .navigationTitle("Pages")
    } detail: {
      detailContent
        .onAppear(perform: flushStartupMessages)
        .navigationTitle(selectedPage.title)
    }
  }

  #if os(macOS)
    // MARK: - Right-to-left sidebar (macOS)

    private var rightSidebarContent: some View {
      HStack(spacing: 0) {
        detailContent
          .onAppear(perform: flushStartupMessages)
          .frame(minWidth: Self.minimumDetailWidth, maxWidth: .infinity, maxHeight: .infinity)
          .environment(\.layoutDirection, swiftUILayoutDirection)

        rightSidebarDivider
        rightSidebarPane
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.background)
    }

    private var rightSidebarPane: some View {
      ZStack {
        Color(nsColor: .windowBackgroundColor)
        sidebarContent(opaqueBackground: true)
      }
      .frame(width: Self.clampedSidebarWidth(rtlSidebarWidth))
      .frame(maxHeight: .infinity)
      .clipped()
      .environment(\.layoutDirection, swiftUILayoutDirection)
    }

    private var rightSidebarDivider: some View {
      ZStack {
        Color.clear
        Rectangle()
          .fill(Color(nsColor: .separatorColor))
          .frame(width: 1)
      }
      .frame(width: 8)
      .contentShape(Rectangle())
      .gesture(
        DragGesture()
          .onChanged { value in
            let startWidth = rtlSidebarDragStartWidth ?? rtlSidebarWidth
            rtlSidebarDragStartWidth = startWidth
            rtlSidebarWidth = Self.clampedSidebarWidth(startWidth - value.translation.width)
          }
          .onEnded { value in
            let startWidth = rtlSidebarDragStartWidth ?? rtlSidebarWidth
            rtlSidebarWidth = Self.clampedSidebarWidth(startWidth - value.translation.width)
            rtlSidebarDragStartWidth = nil
          }
      )
      .onHover { isHovering in
        if isHovering {
          NSCursor.resizeLeftRight.push()
        } else {
          NSCursor.pop()
        }
      }
    }
  #endif

  /// Drains startup diagnostics (workspace bootstrapping notes, config
  /// load receipts) into the terminal once the detail pane appears.
  func flushStartupMessages() {
    let messages = startupMessages
    guard !messages.isEmpty else { return }
    startupMessages.removeAll()
    for message in messages {
      terminal.appendToMain(message)
    }
  }
}

#Preview {
  ContentView(platformName: "Preview")
}
