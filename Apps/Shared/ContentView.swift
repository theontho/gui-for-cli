import Darwin
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
  @State var selectedIconSet: BundleIconSet
  @State var selectedColorTheme: BundleColorTheme
  @State var bundleRootURL: URL?
  @State var startupMessages: [String]
  @State var isTerminalVisible = true
  @State var isSetupRunning = false
  @State var runningSetupStepID: String?
  @State var liveSetupRun: BundleSetupRunState?
  @State var hasAttemptedAutomaticSetup = false
  @State var isRTLSidebarVisible: Bool
  @State var rtlSidebarWidth: CGFloat
  @State var rtlSidebarDragStartWidth: CGFloat?
  @StateObject var terminal: TerminalLogStore
  @StateObject var configStore: BundleConfigStore

  init(
    platformName: String,
    manifest: CLIBundleManifest = DemoBundle.wgsExtract,
    bundleRootURL: URL? = DemoBundle.wgsExtractResourceRootURL
  ) {
    let contentInitStart = Date()
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
    ContentStartupBenchmark.markContentInitialized(since: contentInitStart)
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
      ZStack(alignment: .topTrailing) {
        HStack(spacing: 0) {
          detailContent
            .onAppear(perform: flushStartupMessages)
            .frame(minWidth: Self.minimumDetailWidth, maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.layoutDirection, swiftUILayoutDirection)

          if isRTLSidebarVisible {
            rightSidebarDivider
            rightSidebarPane
          }
        }

        if !isRTLSidebarVisible {
          rtlSidebarToggleButton(
            title: localizationLabels.sidebarShowLabel,
            systemImage: "chevron.left",
            action: { isRTLSidebarVisible = true }
          )
          .padding(12)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.background)
    }

    private var rightSidebarPane: some View {
      ZStack {
        Color(nsColor: .windowBackgroundColor)
        sidebarContent(opaqueBackground: true)
      }
      .overlay(alignment: .topLeading) {
        rtlSidebarToggleButton(
          title: localizationLabels.sidebarHideLabel,
          systemImage: "chevron.right",
          action: { isRTLSidebarVisible = false }
        )
        .padding(10)
      }
      .frame(width: Self.clampedSidebarWidth(rtlSidebarWidth))
      .frame(maxHeight: .infinity)
      .clipped()
      .environment(\.layoutDirection, swiftUILayoutDirection)
    }

    private func rtlSidebarToggleButton(
      title: String,
      systemImage: String,
      action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        Image(systemName: systemImage)
          .frame(width: 26, height: 26)
      }
      .buttonStyle(.borderless)
      .controlSize(.small)
      .help(title)
      .accessibilityLabel(title)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
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

@MainActor
private enum ContentStartupBenchmark {
  private static var didReport = false

  static func markContentInitialized(since start: Date) {
    let benchmarkOutputPath = Self.benchmarkOutputPath()
    guard
      benchmarkOutputPath != nil
        || ProcessInfo.processInfo.environment["GFC_BENCHMARK_STARTUP"] == "1",
      !didReport
    else {
      return
    }
    didReport = true
    let elapsed = Date().timeIntervalSince(start) * 1000
    let message = String(format: "gfc-swiftui benchmark content_initialized_ms=%.1f", elapsed)
    print(message)
    if let outputPath = benchmarkOutputPath {
      appendBenchmarkMessage(message, to: outputPath)
    }
    fflush(stdout)
  }

  private static func benchmarkOutputPath() -> String? {
    let arguments = ProcessInfo.processInfo.arguments
    if let index = arguments.firstIndex(of: "--benchmark-output"),
      arguments.indices.contains(arguments.index(after: index))
    {
      return arguments[arguments.index(after: index)]
    }
    return ProcessInfo.processInfo.environment["GFC_BENCHMARK_OUTPUT"]
  }

  private static func appendBenchmarkMessage(_ message: String, to outputPath: String) {
    let mode = mode_t(S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
    let fd = open(outputPath, O_CREAT | O_WRONLY | O_APPEND, mode)
    guard fd >= 0 else {
      logWriteFailure("open", outputPath: outputPath)
      return
    }
    defer {
      if close(fd) != 0 {
        logWriteFailure("close", outputPath: outputPath)
      }
    }

    let bytes = Array((message + "\n").utf8)
    let didWrite = bytes.withUnsafeBytes { buffer -> Bool in
      guard let baseAddress = buffer.baseAddress else {
        return true
      }
      var offset = 0
      while offset < buffer.count {
        let written = write(fd, baseAddress.advanced(by: offset), buffer.count - offset)
        if written < 0 {
          return false
        }
        offset += written
      }
      return true
    }

    if !didWrite {
      logWriteFailure("write", outputPath: outputPath)
    }
  }

  private static func logWriteFailure(_ operation: String, outputPath: String) {
    let errorMessage = String(cString: strerror(errno))
    fputs(
      "gfc-swiftui benchmark write_failed: \(operation) \(outputPath): \(errorMessage)\n",
      stderr)
  }
}
