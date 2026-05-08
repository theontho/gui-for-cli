import GUIForCLICore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct ContentView: View {
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

private struct InitialConfigValues {
  var values: [String: String]
  var messages: [String]
}

private struct ConfigSettingBinding {
  var control: ControlSpec
  var setting: ConfigSettingSpec
}

private struct SidebarPageGroup: Identifiable {
  let id: String
  let title: String?
  var pages: [BundlePage]

  static func groups(for pages: [BundlePage]) -> [SidebarPageGroup] {
    pages.reduce(into: []) { groups, page in
      let groupTitle = normalizedGroupTitle(page.sidebarGroup)
      if let lastIndex = groups.indices.last, groups[lastIndex].title == groupTitle {
        groups[lastIndex].pages.append(page)
      } else {
        let groupID = "\(groups.count)-\(groupTitle ?? "ungrouped")"
        groups.append(SidebarPageGroup(id: groupID, title: groupTitle, pages: [page]))
      }
    }
  }

  private static func normalizedGroupTitle(_ title: String?) -> String? {
    guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
      return nil
    }
    return title
  }
}

@MainActor
final class AppTextScale: ObservableObject {
  private static let defaultsKey = "appTextScaleStep"
  private static let minimumStep = -3
  private static let maximumStep = 5

  @Published private(set) var step: Int {
    didSet {
      UserDefaults.standard.set(step, forKey: Self.defaultsKey)
    }
  }

  init() {
    step = UserDefaults.standard.integer(forKey: Self.defaultsKey)
    step = Self.clamped(step)
  }

  var dynamicTypeSize: DynamicTypeSize {
    switch step {
    case ...(-3):
      return .xSmall
    case -2:
      return .small
    case -1:
      return .medium
    case 0:
      return .large
    case 1:
      return .xLarge
    case 2:
      return .xxLarge
    case 3:
      return .xxxLarge
    case 4:
      return .accessibility1
    default:
      return .accessibility2
    }
  }

  var canIncrease: Bool { step < Self.maximumStep }
  var canDecrease: Bool { step > Self.minimumStep }
  var canReset: Bool { step != 0 }

  func increase() {
    step = Self.clamped(step + 1)
  }

  func decrease() {
    step = Self.clamped(step - 1)
  }

  func reset() {
    step = 0
  }

  private static func clamped(_ step: Int) -> Int {
    min(max(step, minimumStep), maximumStep)
  }
}

#Preview {
  ContentView(platformName: "Preview")
}

private struct BundleHeader: View {
  let manifest: CLIBundleManifest
  let rootURL: URL?

  var body: some View {
    VStack(spacing: 10) {
      if manifest.sidebarIconStyle != .hidden {
        BundleIconView(manifest: manifest, rootURL: rootURL, size: 72)
      }

      HStack(spacing: 6) {
        InfoLabel(
          text: manifest.displayName,
          tooltip: manifest.summary,
          font: .headline.weight(.semibold)
        )
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, alignment: .center)
    }
  }
}

private struct BundleIconView: View {
  let manifest: CLIBundleManifest
  let rootURL: URL?
  var size: CGFloat = 34

  var body: some View {
    iconContent
      .frame(width: size, height: size)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.22))
  }

  @ViewBuilder private var iconContent: some View {
    switch manifest.sidebarIconStyle {
    case .automatic:
      if let image = bundleImage {
        imageIcon(image)
      } else if let emoji = nonEmptyEmoji {
        emojiIcon(emoji)
      } else {
        symbolIcon
      }
    case .image:
      if let image = bundleImage {
        imageIcon(image)
      } else {
        symbolIcon
      }
    case .emoji:
      if let emoji = nonEmptyEmoji {
        emojiIcon(emoji)
      } else {
        symbolIcon
      }
    case .symbol, .hidden:
      symbolIcon
    }
  }

  private func imageIcon(_ image: Image) -> some View {
    image
      .resizable()
      .scaledToFit()
  }

  private func emojiIcon(_ emoji: String) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        .fill(
          LinearGradient(
            colors: [.accentColor.opacity(0.85), .accentColor.opacity(0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
        )
      Text(emoji)
        .font(.system(size: size * 0.54))
    }
  }

  private var symbolIcon: some View {
    Image(systemName: manifest.iconName)
      .resizable()
      .scaledToFit()
      .foregroundStyle(.tint)
      .padding(size * 0.2)
  }

  private var bundleImage: Image? {
    guard let rootURL, let iconPath = manifest.iconPath, !iconPath.isEmpty else {
      return nil
    }
    let url = rootURL.appendingPathComponent(iconPath, isDirectory: false)
    #if os(macOS)
      guard let image = NSImage(contentsOf: url) else { return nil }
      return Image(nsImage: image)
    #else
      guard let image = UIImage(contentsOfFile: url.path) else { return nil }
      return Image(uiImage: image)
    #endif
  }

  private var nonEmptyEmoji: String? {
    guard let emoji = manifest.iconEmoji, !emoji.isEmpty else {
      return nil
    }
    return emoji
  }
}

struct IconTitleLabel: View {
  @Environment(\.layoutDirection) private var layoutDirection
  let title: String
  let iconName: String?
  let iconEmoji: String?
  let defaultSystemImage: String
  var iconOnly = false

  var body: some View {
    if let iconEmoji, !iconEmoji.isEmpty {
      HStack(spacing: iconOnly ? 0 : 6) {
        Text(iconEmoji)
        if !iconOnly {
          Text(title)
        }
      }
      .accessibilityLabel(title)
    } else {
      if iconOnly {
        systemImage
          .accessibilityLabel(title)
      } else {
        HStack(spacing: 6) {
          systemImage
          Text(title)
        }
        .accessibilityLabel(title)
      }
    }
  }

  private var systemImageName: String {
    iconName.nonEmpty ?? defaultSystemImage
  }

  private var systemImage: some View {
    Image(systemName: systemImageName)
      .scaleEffect(x: shouldMirrorSystemImage ? -1 : 1, y: 1)
  }

  private var shouldMirrorSystemImage: Bool {
    layoutDirection == .rightToLeft && systemImageName == "play"
  }
}

struct ConfigEditorControl: View {
  let control: ControlSpec
  let localizationLabels: BundleLocalizationLabels
  @Binding var fieldValues: [String: String]
  @Binding var configValues: [String: String]
  @Binding var configFilePaths: [String: String]
  let bundleRootURL: URL?
  var loadConfig: (ControlSpec) -> Void
  var persistConfigFilePath: (String, ControlSpec) -> Void
  var configSettingChanged: (String, ConfigSettingSpec, ControlSpec) -> Void
  @State private var showsManualLoadButton = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      InfoLabel(text: control.label, tooltip: control.tooltip, font: .headline)

      if control.configFile != nil {
        LeadingFormRow {
          Text(localizationLabels.settingsFileLabel)
            .font(.headline)
        } content: {
          HStack {
            TextField("config/settings.toml", text: configFilePathBinding)
              .font(.body.monospaced())
            PathPickerButton(
              path: configFilePathBinding,
              labels: localizationLabels,
              canChooseDirectories: false,
              rootURL: bundleRootURL,
              onChoose: configFileChosen)
            if showsManualLoadButton {
              Button {
                showsManualLoadButton = false
                loadConfig(control)
              } label: {
                Label(localizationLabels.loadButtonTitle, systemImage: "arrow.clockwise")
              }
            }
          }
        }
      }

      ForEach(control.settings) { setting in
        ConfigSettingRenderer(
          setting: setting,
          value: binding(for: setting),
          localizationLabels: localizationLabels,
          bundleRootURL: bundleRootURL,
          context: dataSourceContext)
      }
    }
    .help(control.tooltip ?? "")
  }

  private func binding(for setting: ConfigSettingSpec) -> Binding<String> {
    Binding(
      get: {
        if let fieldKey = boundFieldKey(for: setting), let value = fieldValues[fieldKey] {
          return value
        }
        return configValues[control.configValueKey(for: setting), default: setting.value ?? ""]
      },
      set: { newValue in
        configSettingChanged(newValue, setting, control)
      }
    )
  }

  private var configFilePathBinding: Binding<String> {
    Binding(
      get: { configFilePaths[control.id, default: control.configFile?.path ?? ""] },
      set: { newPath in
        configFilePaths[control.id] = newPath
        persistConfigFilePath(newPath, control)
        showsManualLoadButton = true
      }
    )
  }

  private func configFileChosen(_ url: URL) {
    showsManualLoadButton = false
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else { return }
    loadConfig(control)
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

  private var dataSourceContext: CommandRenderContext {
    var settingValues = configValues
    for setting in control.settings {
      let value = configValues[control.configValueKey(for: setting), default: setting.value ?? ""]
      settingValues[setting.id] = value
      settingValues[setting.key] = value
    }
    return CommandRenderContext(
      fieldValues: fieldValues.merging(settingValues) { _, settingValue in settingValue },
      configValues: settingValues,
      bundleRootPath: bundleRootURL?.path)
  }
}

struct ConfigSettingRenderer: View {
  let setting: ConfigSettingSpec
  @Binding var value: String
  let localizationLabels: BundleLocalizationLabels
  let bundleRootURL: URL?
  let context: CommandRenderContext
  @State private var dynamicOptions: [ControlOption]?
  @State private var dataSourceError: String?

  var body: some View {
    let renderedOptions = dynamicOptions ?? setting.options
    LeadingFormRow {
      InfoLabel(text: setting.label, tooltip: setting.tooltip)
    } content: {
      switch setting.kind {
      case .dropdown:
        Picker("", selection: $value) {
          ForEach(renderedOptions) { option in
            Text(displayTitle(for: option)).tag(option.id)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
      case .toggle:
        Toggle("", isOn: Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" }))
          .labelsHidden()
      default:
        HStack {
          TextField(setting.placeholder ?? "", text: $value)
          if setting.kind == .path {
            PathPickerButton(path: $value, labels: localizationLabels, rootURL: bundleRootURL)
          }
        }
      }
    }
    .help(setting.tooltip ?? "")
    .overlay(alignment: .bottomLeading) {
      if let dataSourceError {
        Text(dataSourceError)
          .font(.caption)
          .foregroundStyle(.orange)
          .padding(.top, 4)
      }
    }
    .task(id: dataSourceTaskID) {
      await loadDataSourceIfNeeded()
    }
  }

  private var dataSourceTaskID: String {
    guard let dataSource = setting.dataSource else { return "" }
    return DataSourceRunner.signature(
      dataSource: dataSource,
      rootURL: bundleRootURL,
      context: context)
  }

  private func loadDataSourceIfNeeded() async {
    guard let dataSource = setting.dataSource, let bundleRootURL else { return }
    do {
      let payload = try await DataSourceRunner.load(
        dataSource: dataSource,
        rootURL: bundleRootURL,
        context: context)
      dynamicOptions = payload.options
      selectDefaultOptionIfNeeded(payload.options)
      dataSourceError = nil
    } catch {
      dataSourceError = "Could not load \(setting.label): \(error.localizedDescription)"
    }
  }

  private func selectDefaultOptionIfNeeded(_ options: [ControlOption]?) {
    guard let options else {
      return
    }
    let currentValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !currentValue.isEmpty, options.contains(where: { $0.id == currentValue }) {
      return
    }
    if let defaultOption = options.first(where: \.selected) ?? options.first {
      value = defaultOption.id
    } else if !currentValue.isEmpty {
      value = ""
    }
  }

  private func displayTitle(for option: ControlOption) -> String {
    guard let status = option.status, !status.isEmpty else { return option.title }
    let localized =
      localizationLabels.libraryStatusLabels[status.lowercased()] ?? status
    return "\(option.title) (\(localized))"
  }
}

struct LeadingFormRow<Label: View, Content: View>: View {
  let label: Label
  let content: Content

  init(@ViewBuilder label: () -> Label, @ViewBuilder content: () -> Content) {
    self.label = label()
    self.content = content()
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      label
        .frame(width: 190, alignment: .leading)
      content
        .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct PathPickerButton: View {
  @Binding var path: String
  var labels = BundleLocalizationLabels()
  var canChooseFiles = true
  var canChooseDirectories = true
  var rootURL: URL?
  var onChoose: (URL) -> Void = { _ in }
  @State private var isImportingPath = false
  @State private var pickerErrorMessage = ""
  @State private var isShowingPickerError = false

  var body: some View {
    Button(labels.chooseButtonTitle) {
      choosePath()
    }
    .fileImporter(
      isPresented: $isImportingPath,
      allowedContentTypes: importableContentTypes,
      allowsMultipleSelection: false
    ) { result in
      handleImportedPath(result)
    }
    .alert(labels.pathPickerErrorTitle, isPresented: $isShowingPickerError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(pickerErrorMessage)
    }
  }

  private func choosePath() {
    #if os(macOS)
      let panel = NSOpenPanel()
      panel.canChooseFiles = canChooseFiles
      panel.canChooseDirectories = canChooseDirectories
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = true
      panel.resolvesAliases = true
      if let initialDirectoryURL = initialDirectoryURL(for: path) {
        panel.directoryURL = initialDirectoryURL
      }

      guard panel.runModal() == .OK, let url = panel.url else {
        return
      }
      path = url.path
      onChoose(url)
    #else
      isImportingPath = true
    #endif
  }

  private func handleImportedPath(_ result: Result<[URL], Error>) {
    do {
      guard let url = try result.get().first else {
        return
      }
      path = url.path
      onChoose(url)
    } catch {
      pickerErrorMessage = error.localizedDescription
      isShowingPickerError = true
    }
  }

  private func initialDirectoryURL(for path: String) -> URL? {
    let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPath.isEmpty else { return nil }

    let expandedPath =
      if let rootURL {
        BundlePathResolver.expand(trimmedPath, rootURL: rootURL)
      } else {
        trimmedPath
      }
    let filePath = (expandedPath as NSString).expandingTildeInPath
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory) {
      let url = URL(fileURLWithPath: filePath, isDirectory: isDirectory.boolValue)
        .standardizedFileURL
      return isDirectory.boolValue ? url : url.deletingLastPathComponent()
    }

    let parentURL = URL(fileURLWithPath: filePath, isDirectory: false)
      .standardizedFileURL
      .deletingLastPathComponent()
    var parentIsDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: parentURL.path, isDirectory: &parentIsDirectory),
      parentIsDirectory.boolValue
    else {
      return nil
    }
    return parentURL
  }

  private var importableContentTypes: [UTType] {
    var types: [UTType] = []
    if canChooseFiles {
      types.append(.item)
    }
    if canChooseDirectories {
      types.append(.folder)
    }
    return types.isEmpty ? [.item] : types
  }
}

struct CommandRenderContext: Sendable {
  var fieldValues: [String: String] = [:]
  var checkedOptions: [String: String] = [:]
  var configValues: [String: String] = [:]
  var rowValues: [String: String] = [:]
  var bundleRootPath: String?

  func value(for placeholder: String) -> String? {
    if placeholder == "bundleRoot" || placeholder == "bundleWorkspace" {
      return bundleRootPath
    }
    if placeholder.hasPrefix("row.") {
      return rowValues[String(placeholder.dropFirst(4))]
    }
    if placeholder.hasPrefix("config.") {
      return configValues[String(placeholder.dropFirst(7))]
    }
    if let computedValue = computedFileStateValue(for: placeholder) {
      return computedValue
    }
    return rowValues[placeholder]
      ?? checkedOptions[placeholder]
      ?? fieldValues[placeholder]
      ?? configValues[placeholder]
  }

  func interpolated(_ value: String) -> String {
    var result = value
    let pattern = #"\{\{([^}]+)\}\}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return result
    }
    let matches = regex.matches(
      in: value,
      range: NSRange(value.startIndex..<value.endIndex, in: value))
    for match in matches.reversed() {
      guard
        let placeholderRange = Range(match.range(at: 1), in: value),
        let replacementRange = Range(match.range(at: 0), in: result)
      else {
        continue
      }
      let placeholder = String(value[placeholderRange]).trimmingCharacters(in: .whitespaces)
      result.replaceSubrange(replacementRange, with: self.value(for: placeholder) ?? "")
    }
    return result
  }

  private func computedFileStateValue(for placeholder: String) -> String? {
    guard
      let separator = placeholder.lastIndex(of: "."),
      placeholder.index(after: separator) < placeholder.endIndex
    else {
      return nil
    }

    let fieldID = String(placeholder[..<separator])
    let property = String(placeholder[placeholder.index(after: separator)...])

    switch property {
    case "pathExtension":
      guard let path = fieldValues[fieldID]?.nonEmpty ?? configValues[fieldID]?.nonEmpty else {
        return ""
      }
      return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        .pathExtension.lowercased()
    case "isIndexed":
      guard let path = fieldValues[fieldID]?.nonEmpty ?? configValues[fieldID]?.nonEmpty else {
        return Self.boolString(false)
      }
      return Self.boolString(Self.isIndexedAlignment(path: path))
    case "isSorted":
      guard let path = fieldValues[fieldID]?.nonEmpty ?? configValues[fieldID]?.nonEmpty else {
        return Self.boolString(false)
      }
      return Self.boolString(Self.isSortedAlignment(path: path))
    case "exists":
      guard let path = fieldValues[fieldID]?.nonEmpty ?? configValues[fieldID]?.nonEmpty else {
        return Self.boolString(false)
      }
      let expanded = (path as NSString).expandingTildeInPath
      return Self.boolString(FileManager.default.fileExists(atPath: expanded))
    case "fileSize":
      guard let bytes = Self.fileByteSize(fieldValues[fieldID] ?? configValues[fieldID]) else {
        return ""
      }
      return String(bytes)
    case "fileSizeGB":
      guard let bytes = Self.fileByteSize(fieldValues[fieldID] ?? configValues[fieldID]) else {
        return ""
      }
      let gb = Double(bytes) / 1_073_741_824.0
      return String(format: "%.2f", gb)
    case "parentDir":
      guard let path = fieldValues[fieldID]?.nonEmpty ?? configValues[fieldID]?.nonEmpty else {
        return ""
      }
      let expanded = (path as NSString).expandingTildeInPath
      return URL(fileURLWithPath: expanded).deletingLastPathComponent().path
    default:
      return nil
    }
  }

  private static func fileByteSize(_ raw: String?) -> Int64? {
    guard let raw = raw?.nonEmpty else { return nil }
    let expanded = (raw as NSString).expandingTildeInPath
    guard
      let attrs = try? FileManager.default.attributesOfItem(atPath: expanded),
      let size = attrs[.size] as? NSNumber
    else {
      return nil
    }
    return size.int64Value
  }

  private static func boolString(_ value: Bool) -> String {
    value ? "true" : "false"
  }

  private static func isIndexedAlignment(path: String) -> Bool {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let indexPaths = [
      "\(url.path).bai",
      "\(url.path).crai",
      "\(url.path).csi",
      url.deletingPathExtension().appendingPathExtension("bai").path,
      url.deletingPathExtension().appendingPathExtension("crai").path,
      url.deletingPathExtension().appendingPathExtension("csi").path,
    ]
    return indexPaths.contains { FileManager.default.fileExists(atPath: $0) }
  }

  private static func isSortedAlignment(path: String) -> Bool {
    if isIndexedAlignment(path: path) {
      return true
    }
    let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
    return filename.contains(".sorted.") || filename.contains("_sorted.")
      || filename.hasSuffix(".sorted.bam") || filename.hasSuffix(".sorted.cram")
      || filename.contains(".sort.") || filename.contains("_sort.")
  }
}

private struct CommandRenderContextKey: EnvironmentKey {
  static let defaultValue = CommandRenderContext()
}

private struct BundleLocalizationLabelsKey: EnvironmentKey {
  static let defaultValue = BundleLocalizationLabels()
}

extension EnvironmentValues {
  var commandRenderContext: CommandRenderContext {
    get { self[CommandRenderContextKey.self] }
    set { self[CommandRenderContextKey.self] = newValue }
  }

  var bundleLocalizationLabels: BundleLocalizationLabels {
    get { self[BundleLocalizationLabelsKey.self] }
    set { self[BundleLocalizationLabelsKey.self] = newValue }
  }
}

private extension CLIBundleManifest {
  var initialFieldValues: [String: String] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
      .filter { $0.kind.persistsFieldValue }
      .reduce(into: [:]) { values, control in
        values[control.id] = control.value ?? values[control.id] ?? ""
      }
  }

  var initialCheckedOptions: [String: Set<String>] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
      .filter { $0.kind == .checkboxGroup }
      .reduce(into: [:]) { values, control in
        values[control.id] = Set(control.options.filter(\.selected).map(\.id))
      }
  }

  var initialConfigValues: [String: String] {
    configEditorControls
      .reduce(into: [:]) { values, control in
        for setting in control.settings {
          values[control.configValueKey(for: setting)] = setting.value ?? ""
        }
      }
  }

  var statefulValueControls: [ControlSpec] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
      .filter { $0.kind.persistsFieldValue }
  }

  var checkboxControls: [ControlSpec] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
      .filter { $0.kind == .checkboxGroup }
  }

}

extension ControlSpec {
  func configValueKey(for setting: ConfigSettingSpec) -> String {
    "\(id).\(setting.id)"
  }

  var hydratedRows: [ListRowSpec] {
    guard !items.isEmpty else {
      return rows
    }

    let template =
      rowTemplate
      ?? ListRowSpec(
        id: "{{id}}",
        title: "{{name}}",
        values: Dictionary(uniqueKeysWithValues: columns.map { ($0.id, "{{\($0.id)}}") }),
        status: "{{status}}")

    return items.enumerated().map { index, item in
      let fallbackID = item.values["id"].nonEmpty ?? "row-\(index + 1)"
      let id = interpolate(template.id, values: item.values).nonEmpty ?? fallbackID
      let values = template.values.mapValues { interpolate($0, values: item.values) }
      let title = template.title.map { interpolate($0, values: item.values) }.nonEmpty
      let status = template.status.map { interpolate($0, values: item.values) }.nonEmpty
      let tags =
        template.tags.map {
          TagSpec(
            id: interpolate($0.id, values: item.values),
            title: interpolate($0.title, values: item.values),
            style: $0.style)
        }
        .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      let tooltip = template.tooltip.map { interpolate($0, values: item.values) }.nonEmpty

      return ListRowSpec(
        id: id,
        title: title,
        values: values,
        status: status,
        tags: tags,
        tooltip: tooltip)
    }
  }

  private func interpolate(_ value: String, values: [String: String]) -> String {
    var result = value
    let pattern = #"\{\{([^}]+)\}\}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return result
    }
    let matches = regex.matches(
      in: value,
      range: NSRange(value.startIndex..<value.endIndex, in: value))
    for match in matches.reversed() {
      guard
        let placeholderRange = Range(match.range(at: 1), in: value),
        let replacementRange = Range(match.range(at: 0), in: result)
      else {
        continue
      }
      let rawPlaceholder = String(value[placeholderRange]).trimmingCharacters(in: .whitespaces)
      let placeholder =
        rawPlaceholder.hasPrefix("item.") ? String(rawPlaceholder.dropFirst(5)) : rawPlaceholder
      result.replaceSubrange(replacementRange, with: values[placeholder] ?? "")
    }
    return result
  }
}

private extension ControlKind {
  var persistsFieldValue: Bool {
    switch self {
    case .text, .path, .dropdown, .toggle:
      true
    case .checkboxGroup, .infoGrid, .libraryList, .configEditor:
      false
    }
  }
}

extension Optional where Wrapped == String {
  var nonEmpty: String? {
    guard let value = self else { return nil }
    return value.nonEmpty
  }
}

extension String {
  var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
#if os(macOS)
  private struct NativeTerminalSplitView<TopContent: View, BottomContent: View>: NSViewRepresentable
  {
    let topContent: TopContent
    let bottomContent: BottomContent
    let initialBottomFraction: CGFloat
    let minimumTopHeight: CGFloat
    let minimumBottomHeight: CGFloat

    func makeCoordinator() -> Coordinator {
      Coordinator(
        initialBottomFraction: initialBottomFraction,
        minimumTopHeight: minimumTopHeight,
        minimumBottomHeight: minimumBottomHeight)
    }

    func makeNSView(context: Context) -> NSSplitView {
      let splitView = NSSplitView()
      splitView.isVertical = false
      splitView.dividerStyle = .thin

      let bottomHostingView = NSHostingView(rootView: bottomContent)
      let topHostingView = NSHostingView(rootView: topContent)
      context.coordinator.bottomHostingView = bottomHostingView
      context.coordinator.topHostingView = topHostingView

      splitView.addArrangedSubview(topHostingView)
      splitView.addArrangedSubview(bottomHostingView)
      context.coordinator.scheduleInitialPosition(in: splitView)
      return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
      context.coordinator.bottomHostingView?.rootView = bottomContent
      context.coordinator.topHostingView?.rootView = topContent
      context.coordinator.scheduleInitialPosition(in: splitView)
    }

    @MainActor final class Coordinator: NSObject {
      var topHostingView: NSHostingView<TopContent>?
      var bottomHostingView: NSHostingView<BottomContent>?

      private let initialBottomFraction: CGFloat
      private let minimumTopHeight: CGFloat
      private let minimumBottomHeight: CGFloat
      private var didSetInitialPosition = false

      init(
        initialBottomFraction: CGFloat,
        minimumTopHeight: CGFloat,
        minimumBottomHeight: CGFloat
      ) {
        self.initialBottomFraction = initialBottomFraction
        self.minimumTopHeight = minimumTopHeight
        self.minimumBottomHeight = minimumBottomHeight
      }

      func scheduleInitialPosition(in splitView: NSSplitView) {
        guard !didSetInitialPosition else { return }
        Task { @MainActor [weak self, weak splitView] in
          guard let self, let splitView else { return }
          self.applyInitialPosition(in: splitView)
        }
      }

      private func applyInitialPosition(in splitView: NSSplitView) {
        guard splitView.bounds.height > 0 else {
          scheduleInitialPosition(in: splitView)
          return
        }
        let maximumBottomHeight = max(
          minimumBottomHeight,
          splitView.bounds.height - minimumTopHeight - splitView.dividerThickness)
        let bottomHeight = min(
          max(splitView.bounds.height * initialBottomFraction, minimumBottomHeight),
          maximumBottomHeight)
        let topHeight = splitView.bounds.height - bottomHeight - splitView.dividerThickness
        splitView.setPosition(topHeight, ofDividerAt: 0)
        didSetInitialPosition = true
      }
    }
  }
#endif
