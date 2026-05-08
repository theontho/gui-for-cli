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
  private let bundleSourceRootURL: URL?

  @State private var manifest: CLIBundleManifest
  @State private var selectedPageID: String?
  @State private var selectedLocalizationCode: String
  @State private var usingSystemDefaultLocale: Bool
  @State private var localizationOptions: [BundleLocalizationOption]
  @State private var localizationLabels: BundleLocalizationLabels
  @State private var fieldValues: [String: String]
  @State private var checkedOptions: [String: Set<String>]
  @State private var configValues: [String: String]
  @State private var configFilePaths: [String: String]
  @State private var bundleRootURL: URL?
  @State private var startupMessages: [String]
  @State private var isTerminalVisible = true
  @State private var rtlSidebarWidth: CGFloat
  @State private var rtlSidebarDragStartWidth: CGFloat?
  @StateObject private var terminal: TerminalLogStore

  init(
    platformName: String,
    manifest: CLIBundleManifest = DemoBundle.wgsExtract,
    bundleRootURL: URL? = DemoBundle.wgsExtractResourceRootURL
  ) {
    self.platformName = platformName
    let sourceBundleRootURL = bundleRootURL ?? DemoBundle.wgsExtractResourceRootURL
    self.bundleSourceRootURL = sourceBundleRootURL
    let storedLocalizationCode = UserDefaults.standard.string(
      forKey: Self.localizationDefaultsKey(bundleID: manifest.id))
    let probe = try? BundleSourceLoader().load(from: sourceBundleRootURL)
    let availableOptions = probe?.localizationOptions ?? []
    let resolvedRequest =
      storedLocalizationCode
      ?? BundleSourceLoader.matchLocalizationCode(
        preferences: Self.systemPreferredLocalizations(),
        options: availableOptions)
    let loadedBundle = try? BundleSourceLoader().load(
      from: sourceBundleRootURL,
      localizationCode: resolvedRequest)
    let activeManifest = loadedBundle?.manifest ?? manifest
    let preparedWorkspace = Self.prepareBundleWorkspace(
      for: activeManifest,
      sourceRootURL: sourceBundleRootURL)
    let configFilePaths = Self.initialConfigFilePaths(for: activeManifest)
    let bootstrapMessages = Self.bootstrapConfigFiles(
      for: activeManifest,
      rootURL: preparedWorkspace.rootURL,
      configFilePaths: configFilePaths)
    let loadedConfig = Self.initialConfigValues(
      for: activeManifest,
      rootURL: preparedWorkspace.rootURL,
      configFilePaths: configFilePaths)
    let configValues = loadedConfig.values
    _manifest = State(initialValue: activeManifest)
    _selectedPageID = State(initialValue: activeManifest.pages.first?.id)
    _selectedLocalizationCode = State(
      initialValue: loadedBundle?.localizationCode ?? BundleSourceLoader.defaultLocalizationCode)
    _usingSystemDefaultLocale = State(initialValue: storedLocalizationCode == nil)
    _localizationOptions = State(initialValue: loadedBundle?.localizationOptions ?? [])
    _localizationLabels = State(
      initialValue: loadedBundle?.localizationLabels ?? BundleLocalizationLabels())
    _fieldValues = State(
      initialValue: Self.initialFieldValues(for: activeManifest, configValues: configValues))
    _checkedOptions = State(
      initialValue: Self.initialCheckedOptions(for: activeManifest, configValues: configValues))
    _configValues = State(initialValue: configValues)
    _configFilePaths = State(initialValue: configFilePaths)
    _bundleRootURL = State(initialValue: preparedWorkspace.rootURL)
    _startupMessages = State(
      initialValue: preparedWorkspace.messages + bootstrapMessages + loadedConfig.messages)
    _rtlSidebarWidth = State(initialValue: Self.sidebarWidth)
    _rtlSidebarDragStartWidth = State(initialValue: nil)
    _terminal = StateObject(
      wrappedValue: TerminalLogStore(
        exitCodeReference: activeManifest.effectiveExitCodeReference,
        localizationLabels: loadedBundle?.localizationLabels ?? BundleLocalizationLabels()))
  }

  // MARK: - Body

  var body: some View {
    rootContent
      .environmentObject(terminal)
      .onAppear {
        if let bundleSourceRootURL, BundleHotReloader.isEnabled {
          BundleHotReloader.shared.start(at: bundleSourceRootURL)
        }
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

  // MARK: - Sidebar

  private func sidebarContent(opaqueBackground: Bool) -> some View {
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

  private func sidebarBackgroundColor(opaque: Bool) -> Color {
    guard opaque else { return Color.clear }
    #if os(macOS)
      return Color(nsColor: .windowBackgroundColor)
    #else
      return Color(uiColor: .systemBackground)
    #endif
  }

  #if os(macOS)
    private static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
      min(max(width, minimumSidebarWidth), maximumSidebarWidth)
    }
  #endif

  private var primarySidebarPages: [BundlePage] {
    manifest.pages.filter { !Self.bottomSidebarPageIDs.contains($0.id) }
  }

  private var primarySidebarGroups: [SidebarPageGroup] {
    SidebarPageGroup.groups(for: primarySidebarPages)
  }

  private var bottomSidebarPages: [BundlePage] {
    manifest.pages.filter { Self.bottomSidebarPageIDs.contains($0.id) }
  }

  private func sidebarPageLabel(for page: BundlePage) -> some View {
    IconTitleLabel(
      title: page.title,
      iconName: page.iconName,
      iconEmoji: page.iconEmoji,
      defaultSystemImage: "doc.text"
    )
    .tag(page.id)
  }

  private static let bottomSidebarPageIDs: Set<String> = ["library", "settings"]
  private static let sidebarWidth: CGFloat = 220
  private static let minimumSidebarWidth: CGFloat = 160
  private static let maximumSidebarWidth: CGFloat = 420
  private static let minimumDetailWidth: CGFloat = 520

  // MARK: - Detail pane

  @ViewBuilder private var detailContent: some View {
    #if os(macOS)
      ZStack(alignment: .bottomTrailing) {
        if isTerminalVisible {
          NativeTerminalSplitView(
            topContent: pageContent,
            bottomContent: TerminalPane(
              store: terminal,
              labels: localizationLabels,
              textDirection: terminalTextLayoutDirection),
            initialBottomFraction: Self.initialTerminalHeightFraction,
            minimumTopHeight: Self.minimumPageHeight,
            minimumBottomHeight: Self.minimumTerminalHeight
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          VStack(spacing: 0) {
            pageContent
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        terminalVisibilityButton
          .padding(.trailing, 16)
          .padding(.bottom, 12)
      }
    #else
      ZStack(alignment: .bottomTrailing) {
        VStack(spacing: 0) {
          pageContent

          if isTerminalVisible {
            Divider()
            TerminalPane(
              store: terminal,
              labels: localizationLabels,
              textDirection: terminalTextLayoutDirection
            )
            .frame(height: 240)
          }
        }

        terminalVisibilityButton
          .padding(.trailing, 16)
          .padding(.bottom, 12)
      }
    #endif
  }

  private var terminalVisibilityButton: some View {
    let title =
      isTerminalVisible
      ? localizationLabels.terminalHideOutputLabel
      : localizationLabels.terminalShowOutputLabel
    return Button {
      isTerminalVisible.toggle()
    } label: {
      Label(title, systemImage: "rectangle.bottomthird.inset.filled")
        .labelStyle(.iconOnly)
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .accessibilityLabel(title)
    .help(title)
  }

  private static let initialTerminalHeightFraction: CGFloat = 0.20
  private static let minimumTerminalHeight: CGFloat = 96
  private static let minimumPageHeight: CGFloat = 260

  private var pageContent: some View {
    PageRenderer(
      page: selectedPage,
      localizationLabels: localizationLabels,
      fieldValues: $fieldValues,
      checkedOptions: $checkedOptions,
      configValues: $configValues,
      configFilePaths: $configFilePaths,
      bundleRootURL: bundleRootURL,
      runAction: { action, context in
        let command = action.command.renderedCommand(resolving: context)
        terminal.start(
          title: action.title,
          command: command,
          workingDirectory: bundleRootURL)
      },
      saveConfig: { control in
        saveConfig(control)
      },
      loadConfig: { control in
        loadConfig(control)
      },
      persistConfigFilePath: { path, control in
        persistConfigFilePath(path, for: control)
      },
      fieldValueChanged: { value, control in
        fieldValueChanged(value, for: control)
      },
      checkedOptionsChanged: { selectedIDs, control in
        checkedOptionsChanged(selectedIDs, for: control)
      },
      configSettingChanged: { value, setting, control in
        configSettingChanged(value, for: setting, in: control)
      },
      headerAccessory: settingsLanguageAccessory
    )
    .environment(\.layoutDirection, swiftUILayoutDirection)
  }

  private var selectedPage: BundlePage {
    manifest.pages.first { $0.id == selectedPageID } ?? manifest.pages[0]
  }

  private var swiftUILayoutDirection: LayoutDirection {
    localizationLabels.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
  }

  private var terminalTextLayoutDirection: LayoutDirection {
    manifest.terminalTextDirection == .rightToLeft ? .rightToLeft : .leftToRight
  }

  // MARK: - Bundle workspace

  private static func prepareBundleWorkspace(
    for manifest: CLIBundleManifest,
    sourceRootURL: URL
  ) -> (rootURL: URL, messages: [String]) {
    let workspaceURL = AppPaths.bundleWorkspaceDirectory(for: manifest.id)
    do {
      try BundleSourceLoader().syncBundleWorkspace(from: sourceRootURL, to: workspaceURL)
      return (
        workspaceURL,
        ["[bundle] Using persistent workspace: \(workspaceURL.path)"]
      )
    } catch {
      return (
        sourceRootURL,
        [
          "[bundle:error] Could not prepare persistent workspace: \(error.localizedDescription)",
          "[bundle] Falling back to bundle source: \(sourceRootURL.path)",
        ]
      )
    }
  }

  // MARK: - Config save / load

  private func saveConfig(_ control: ControlSpec, reportSuccess: Bool = true) {
    guard control.configFile != nil else {
      terminal.appendToMain("[config:error] \(control.label) does not specify a config file.")
      return
    }
    guard let configURL = resolvedConfigURL(for: control) else {
      terminal.appendToMain("[config:error] Choose a settings file path before saving.")
      return
    }

    do {
      try FileManager.default.createDirectory(
        at: configURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      let contents = try configContents(for: control, existingAt: configURL)
      try contents.write(to: configURL, atomically: true, encoding: .utf8)
      if reportSuccess {
        terminal.appendToMain(
          "[config] Saved \(control.settings.count) setting(s) to \(configURL.path)")
      }
    } catch {
      terminal.appendToMain("[config:error] \(error.localizedDescription)")
    }
  }

  private func loadConfig(_ control: ControlSpec) {
    guard let configURL = resolvedConfigURL(for: control) else {
      terminal.appendToMain("[config:error] Choose a settings file path before loading.")
      return
    }

    do {
      let text = try String(contentsOf: configURL, encoding: .utf8)
      let fileValues = try FlatTomlDocument.parse(text)
      applyConfigValues(fileValues, for: control)
      terminal.appendToMain("[config] Loaded settings from \(configURL.path)")
    } catch {
      terminal.appendToMain("[config:error] \(error.localizedDescription)")
    }
  }

  private func persistConfigFilePath(_ path: String, for control: ControlSpec) {
    configFilePaths[control.id] = path
    UserDefaults.standard.set(
      path, forKey: Self.configFilePathDefaultsKey(manifest: manifest, control: control))
  }

  // MARK: - Field / option / setting handlers

  private func fieldValueChanged(_ value: String, for control: ControlSpec) {
    fieldValues[control.id] = value
    let bindings = Self.configSettingBindings(in: manifest, forFieldID: control.id)
    guard !bindings.isEmpty else {
      persistFieldValue(value, for: control)
      return
    }

    UserDefaults.standard.removeObject(
      forKey: Self.fieldValueDefaultsKey(manifest: manifest, controlID: control.id))
    for binding in bindings {
      configValues[binding.control.configValueKey(for: binding.setting)] = value
      saveConfig(binding.control, reportSuccess: false)
    }
  }

  private func checkedOptionsChanged(_ selectedIDs: Set<String>, for control: ControlSpec) {
    checkedOptions[control.id] = selectedIDs
    let bindings = Self.configSettingBindings(in: manifest, forFieldID: control.id)
    let value = selectedIDs.sorted().joined(separator: ",")
    guard !bindings.isEmpty else {
      persistCheckedOptions(selectedIDs, for: control)
      return
    }

    UserDefaults.standard.removeObject(
      forKey: Self.checkedOptionsDefaultsKey(manifest: manifest, controlID: control.id))
    for binding in bindings {
      configValues[binding.control.configValueKey(for: binding.setting)] = value
      saveConfig(binding.control, reportSuccess: false)
    }
  }

  private func configSettingChanged(
    _ value: String,
    for setting: ConfigSettingSpec,
    in control: ControlSpec
  ) {
    configValues[control.configValueKey(for: setting)] = value
    if let fieldKey = boundFieldKey(for: setting) {
      fieldValues[fieldKey] = value
      UserDefaults.standard.removeObject(
        forKey: Self.fieldValueDefaultsKey(manifest: manifest, controlID: fieldKey))
    }
    saveConfig(control, reportSuccess: false)
  }

  // MARK: - Localization

  private var settingsLanguageAccessory: AnyView? {
    guard selectedPage.id == "settings", localizationOptions.count > 1 else {
      return nil
    }
    return AnyView(
      LanguageSettingsSection(
        options: localizationOptions,
        labels: localizationLabels,
        selectedCode: selectedLocalizationCode,
        usingSystemDefault: usingSystemDefaultLocale,
        onSelectExplicit: { code in
          applyLocalization(code)
          usingSystemDefaultLocale = false
        },
        onSelectSystemDefault: { resetToSystemLocale() }))
  }

  private func resetToSystemLocale() {
    UserDefaults.standard.removeObject(
      forKey: Self.localizationDefaultsKey(bundleID: manifest.id))
    usingSystemDefaultLocale = true
    let match =
      BundleSourceLoader.matchLocalizationCode(
        preferences: Self.systemPreferredLocalizations(),
        options: localizationOptions) ?? BundleSourceLoader.defaultLocalizationCode
    if match != selectedLocalizationCode {
      applyLocalization(match, persist: false)
    }
  }

  private func applyLocalization(_ code: String, persist: Bool = true) {
    guard let bundleSourceRootURL else {
      return
    }

    do {
      let loadedBundle = try BundleSourceLoader().load(
        from: bundleSourceRootURL,
        localizationCode: code)
      manifest = loadedBundle.manifest
      localizationOptions = loadedBundle.localizationOptions
      localizationLabels = loadedBundle.localizationLabels
      if selectedLocalizationCode != loadedBundle.localizationCode {
        selectedLocalizationCode = loadedBundle.localizationCode
      }
      terminal.updateExitCodeReference(loadedBundle.manifest.effectiveExitCodeReference)
      terminal.updateLocalizationLabels(loadedBundle.localizationLabels)
      if persist {
        UserDefaults.standard.set(
          loadedBundle.localizationCode,
          forKey: Self.localizationDefaultsKey(bundleID: loadedBundle.manifest.id))
        usingSystemDefaultLocale = false
      }
      if selectedPageID.flatMap({ id in loadedBundle.manifest.pages.first { $0.id == id } }) == nil
      {
        selectedPageID = loadedBundle.manifest.pages.first?.id
      }
    } catch {
      terminal.appendToMain("[localization:error] \(error.localizedDescription)")
    }
  }

  // MARK: - Config helpers

  private func resolvedConfigURL(for control: ControlSpec) -> URL? {
    guard let path = configFilePaths[control.id] ?? control.configFile?.path else {
      return nil
    }
    return Self.resolvedConfigURL(path: path, rootURL: bundleRootURL)
  }

  private func configSettingValue(for setting: ConfigSettingSpec, in control: ControlSpec) -> String
  {
    if let fieldKey = boundFieldKey(for: setting), let value = fieldValues[fieldKey] {
      return value
    }
    return configValues[control.configValueKey(for: setting), default: setting.value ?? ""]
  }

  private func configContents(for control: ControlSpec, existingAt configURL: URL) throws -> String
  {
    var values: [String: String] = [:]
    if FileManager.default.fileExists(atPath: configURL.path) {
      let existingText = try String(contentsOf: configURL, encoding: .utf8)
      values = try FlatTomlDocument.parse(existingText)
    }
    for setting in control.settings {
      values[setting.key] = configSettingValue(for: setting, in: control)
    }
    return FlatTomlDocument.string(from: values)
  }

  private func boundFieldKey(for setting: ConfigSettingSpec) -> String? {
    if fieldValues.keys.contains(setting.key) {
      return setting.key
    }
    if fieldValues.keys.contains(setting.id) {
      return setting.id
    }
    return nil
  }

  private func applyConfigValues(_ fileValues: [String: String], for control: ControlSpec) {
    for setting in control.settings {
      guard let value = fileValues[setting.key] else { continue }
      configValues[control.configValueKey(for: setting)] = value
      if let fieldKey = boundFieldKey(for: setting) {
        fieldValues[fieldKey] = value
      }
    }
  }

  private func persistFieldValue(_ value: String, for control: ControlSpec) {
    guard control.kind.persistsFieldValue else { return }
    UserDefaults.standard.set(
      value, forKey: Self.fieldValueDefaultsKey(manifest: manifest, control: control))
  }

  private func persistCheckedOptions(_ selectedIDs: Set<String>, for control: ControlSpec) {
    guard control.kind == .checkboxGroup else { return }
    UserDefaults.standard.set(
      selectedIDs.sorted(),
      forKey: Self.checkedOptionsDefaultsKey(manifest: manifest, control: control))
  }

  private func flushStartupMessages() {
    let messages = startupMessages
    guard !messages.isEmpty else { return }
    startupMessages.removeAll()
    for message in messages {
      terminal.appendToMain(message)
    }
  }

  // MARK: - Initial state factories

  private static func initialConfigFilePaths(for manifest: CLIBundleManifest) -> [String: String] {
    manifest.configEditorControls.reduce(into: [:]) { paths, control in
      guard let configFile = control.configFile else { return }
      let defaultsKey = configFilePathDefaultsKey(manifest: manifest, control: control)
      if let persistedPath = UserDefaults.standard.string(forKey: defaultsKey),
        !shouldDiscardLegacyConfigPath(persistedPath, defaultPath: configFile.path)
      {
        paths[control.id] = persistedPath
      } else {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        paths[control.id] = configFile.path
      }
    }
  }

  private static func shouldDiscardLegacyConfigPath(_ path: String, defaultPath: String) -> Bool {
    guard defaultPath.contains("{{bundleWorkspace}}") else { return false }
    let legacyWGSPath = "/.config/wgsextract/config.toml"
    return path == "{{home}}\(legacyWGSPath)" || path.hasSuffix(legacyWGSPath)
  }

  private static func bootstrapConfigFiles(
    for manifest: CLIBundleManifest,
    rootURL: URL?,
    configFilePaths: [String: String]
  ) -> [String] {
    guard let rootURL else { return [] }
    do {
      return try ConfigFileBootstrapper()
        .bootstrap(manifest: manifest, rootURL: rootURL, pathOverrides: configFilePaths)
        .compactMap { result in
          switch result.status {
          case .created, .merged:
            "[config] \(result.message)"
          case .skippedExisting, .unchanged, .wouldCreate, .wouldMerge, .wouldSkipExisting,
            .wouldLeaveUnchanged:
            nil
          }
        }
    } catch {
      return ["[config:error] \(error.localizedDescription)"]
    }
  }

  private static func initialFieldValues(
    for manifest: CLIBundleManifest, configValues: [String: String]
  )
    -> [String: String]
  {
    var values = manifest.initialFieldValues
    for control in manifest.statefulValueControls
    where configSettingBindings(in: manifest, forFieldID: control.id).isEmpty {
      if let persistedValue = UserDefaults.standard.string(
        forKey: fieldValueDefaultsKey(manifest: manifest, control: control))
      {
        values[control.id] = persistedValue
      }
    }
    for control in manifest.configEditorControls {
      for setting in control.settings {
        let configValue = configValues[
          control.configValueKey(for: setting), default: setting.value ?? ""]
        if values.keys.contains(setting.key) {
          values[setting.key] = configValue
        }
        if values.keys.contains(setting.id) {
          values[setting.id] = configValue
        }
      }
    }
    return values
  }

  private static func initialCheckedOptions(
    for manifest: CLIBundleManifest,
    configValues: [String: String]
  ) -> [String: Set<String>] {
    var values = manifest.initialCheckedOptions
    for control in manifest.checkboxControls {
      let bindings = configSettingBindings(in: manifest, forFieldID: control.id)
      if let binding = bindings.first {
        let configValue =
          configValues[
            binding.control.configValueKey(for: binding.setting),
            default: binding.setting.value ?? "",
          ]
        values[control.id] = Set(
          configValue.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
          }.filter { !$0.isEmpty })
      } else if let persistedIDs = UserDefaults.standard.stringArray(
        forKey: checkedOptionsDefaultsKey(manifest: manifest, control: control))
      {
        values[control.id] = Set(persistedIDs)
      }
    }
    return values
  }

  private static func initialConfigValues(
    for manifest: CLIBundleManifest,
    rootURL: URL?,
    configFilePaths: [String: String]
  )
    -> InitialConfigValues
  {
    var values = manifest.initialConfigValues
    var messages: [String] = []

    for control in manifest.configEditorControls {
      guard
        control.configFile != nil,
        let path = configFilePaths[control.id],
        let configURL = resolvedConfigURL(path: path, rootURL: rootURL)
      else { continue }
      guard FileManager.default.fileExists(atPath: configURL.path) else { continue }
      do {
        let text = try String(contentsOf: configURL, encoding: .utf8)
        let fileValues = try FlatTomlDocument.parse(text)
        for setting in control.settings {
          if let value = fileValues[setting.key] {
            values[control.configValueKey(for: setting)] = value
          }
        }
        messages.append("[config] Loaded settings from \(configURL.path)")
      } catch {
        messages.append(
          "[config:error] Could not load \(configURL.path): \(error.localizedDescription)")
      }
    }
    return InitialConfigValues(values: values, messages: messages)
  }

  private static func resolvedConfigURL(path: String, rootURL: URL?) -> URL? {
    guard let rootURL else { return nil }
    return BundlePathResolver.resolveConfigFilePath(path, rootURL: rootURL)
  }

  private static func configFilePathDefaultsKey(manifest: CLIBundleManifest, control: ControlSpec)
    -> String
  {
    "GUIForCLI.configFilePath.\(manifest.id).\(control.id)"
  }

  private static func fieldValueDefaultsKey(manifest: CLIBundleManifest, control: ControlSpec)
    -> String
  {
    fieldValueDefaultsKey(manifest: manifest, controlID: control.id)
  }

  private static func fieldValueDefaultsKey(manifest: CLIBundleManifest, controlID: String)
    -> String
  {
    "GUIForCLI.fieldValue.\(manifest.id).\(controlID)"
  }

  private static func checkedOptionsDefaultsKey(manifest: CLIBundleManifest, control: ControlSpec)
    -> String
  {
    checkedOptionsDefaultsKey(manifest: manifest, controlID: control.id)
  }

  private static func checkedOptionsDefaultsKey(manifest: CLIBundleManifest, controlID: String)
    -> String
  {
    "GUIForCLI.checkedOptions.\(manifest.id).\(controlID)"
  }

  // MARK: - Defaults keys & system locale

  private static func localizationDefaultsKey(bundleID: String) -> String {
    "GUIForCLI.localization.\(bundleID)"
  }

  /// Re-resolves the active localization when the system locale changes. Honors
  /// any locale the user has explicitly chosen via the in-app picker (stored in
  /// `UserDefaults`) and otherwise falls back to the new best system match
  /// without persisting it.
  private func systemLocaleDidChange() {
    let storedKey = Self.localizationDefaultsKey(bundleID: manifest.id)
    if UserDefaults.standard.string(forKey: storedKey) != nil {
      return
    }
    guard
      let match = BundleSourceLoader.matchLocalizationCode(
        preferences: Self.systemPreferredLocalizations(),
        options: localizationOptions),
      match != selectedLocalizationCode
    else {
      return
    }
    applyLocalization(match, persist: false)
  }

  /// System-preferred locale identifiers, in priority order. Combines
  /// `Locale.preferredLanguages` and the current locale identifier so we
  /// pick up both UI language and region overrides.
  static func systemPreferredLocalizations() -> [String] {
    var seen: Set<String> = []
    var ordered: [String] = []
    for raw in Locale.preferredLanguages + [Locale.current.identifier] {
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
      ordered.append(trimmed)
    }
    return ordered
  }

  private static func configSettingBindings(
    in manifest: CLIBundleManifest,
    forFieldID fieldID: String
  ) -> [ConfigSettingBinding] {
    manifest.configEditorControls.flatMap { control in
      control.settings.compactMap { setting in
        guard setting.id == fieldID || setting.key == fieldID else { return nil }
        return ConfigSettingBinding(control: control, setting: setting)
      }
    }
  }

}

#Preview {
  ContentView(platformName: "Preview")
}
