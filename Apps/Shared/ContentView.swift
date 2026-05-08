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
    Button {
      isTerminalVisible.toggle()
    } label: {
      Label(
        isTerminalVisible ? "Hide Command Output" : "Show Command Output",
        systemImage: "rectangle.bottomthird.inset.filled"
      )
      .labelStyle(.iconOnly)
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .accessibilityLabel(isTerminalVisible ? "Hide Command Output" : "Show Command Output")
    .help(isTerminalVisible ? "Hide Command Output" : "Show Command Output")
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

private struct IconTitleLabel: View {
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

private struct PageRenderer: View {
  let page: BundlePage
  let localizationLabels: BundleLocalizationLabels
  @Binding var fieldValues: [String: String]
  @Binding var checkedOptions: [String: Set<String>]
  @Binding var configValues: [String: String]
  @Binding var configFilePaths: [String: String]
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
  var saveConfig: (ControlSpec) -> Void
  var loadConfig: (ControlSpec) -> Void
  var persistConfigFilePath: (String, ControlSpec) -> Void
  var fieldValueChanged: (String, ControlSpec) -> Void
  var checkedOptionsChanged: (Set<String>, ControlSpec) -> Void
  var configSettingChanged: (String, ConfigSettingSpec, ControlSpec) -> Void
  var headerAccessory: AnyView?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          IconTitleLabel(
            title: page.title,
            iconName: page.iconName,
            iconEmoji: page.iconEmoji,
            defaultSystemImage: "doc.text"
          )
          .font(.largeTitle.weight(.semibold))
          Text(page.summary)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .help(page.summary)
        }

        if let headerAccessory {
          headerAccessory
        }

        ForEach(page.sections) { section in
          SectionRenderer(
            section: section,
            localizationLabels: localizationLabels,
            fieldValues: $fieldValues,
            checkedOptions: $checkedOptions,
            configValues: $configValues,
            configFilePaths: $configFilePaths,
            bundleRootURL: bundleRootURL,
            runAction: runAction,
            saveConfig: saveConfig,
            loadConfig: loadConfig,
            persistConfigFilePath: persistConfigFilePath,
            fieldValueChanged: fieldValueChanged,
            checkedOptionsChanged: checkedOptionsChanged,
            configSettingChanged: configSettingChanged
          )
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(.background)
  }
}

private struct LanguageSettingsSection: View {
  let options: [BundleLocalizationOption]
  let labels: BundleLocalizationLabels
  let selectedCode: String
  let usingSystemDefault: Bool
  var onSelectExplicit: (String) -> Void
  var onSelectSystemDefault: () -> Void

  @State private var isPresenting = false
  @State private var searchText = ""

  private var currentName: String {
    options.first { $0.code == selectedCode }?.displayName ?? selectedCode
  }

  private var buttonLabel: String {
    usingSystemDefault
      ? "\(labels.languageSystemDefaultLabel) — \(currentName)"
      : currentName
  }

  private var filteredOptions: [BundleLocalizationOption] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if query.isEmpty { return options }
    return options.filter { option in
      option.displayName.lowercased().contains(query)
        || option.code.lowercased().contains(query)
    }
  }

  var body: some View {
    GroupBox {
      LeadingFormRow {
        Text(labels.languagePickerLabel)
          .font(.headline)
      } content: {
        Button {
          isPresenting.toggle()
        } label: {
          HStack(spacing: 6) {
            Text(buttonLabel)
              .lineLimit(1)
              .truncationMode(.tail)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: 280, alignment: .leading)
        .popover(isPresented: $isPresenting, arrowEdge: .bottom) {
          languageList
        }
      }
    } label: {
      Label(labels.languageSectionTitle, systemImage: "globe")
    }
  }

  private var languageList: some View {
    VStack(alignment: .leading, spacing: 0) {
      TextField(labels.languageSearchPlaceholder, text: $searchText)
        .textFieldStyle(.roundedBorder)
        .padding(8)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          languageRow(
            title: labels.languageSystemDefaultLabel,
            subtitle: nil,
            isSelected: usingSystemDefault,
            action: {
              isPresenting = false
              onSelectSystemDefault()
            })
          Divider()
          ForEach(filteredOptions) { option in
            languageRow(
              title: option.displayName,
              subtitle: option.code,
              isSelected: !usingSystemDefault && option.code == selectedCode,
              action: {
                isPresenting = false
                onSelectExplicit(option.code)
              })
          }
        }
      }
      .frame(minWidth: 280, maxHeight: 360)
    }
    .frame(minWidth: 280)
  }

  @ViewBuilder
  private func languageRow(
    title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: isSelected ? "checkmark" : "circle")
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
          .frame(width: 16)
        VStack(alignment: .leading, spacing: 1) {
          Text(title)
          if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct SectionRenderer: View {
  @EnvironmentObject private var terminal: TerminalLogStore
  let section: PageSection
  let localizationLabels: BundleLocalizationLabels
  @Binding var fieldValues: [String: String]
  @Binding var checkedOptions: [String: Set<String>]
  @Binding var configValues: [String: String]
  @Binding var configFilePaths: [String: String]
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
  var saveConfig: (ControlSpec) -> Void
  var loadConfig: (ControlSpec) -> Void
  var persistConfigFilePath: (String, ControlSpec) -> Void
  var fieldValueChanged: (String, ControlSpec) -> Void
  var checkedOptionsChanged: (Set<String>, ControlSpec) -> Void
  var configSettingChanged: (String, ConfigSettingSpec, ControlSpec) -> Void
  @State private var sectionValues: [String: String] = [:]
  @State private var dataSourceError: String?

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 16) {
        if let subtitle = section.subtitle {
          Text(subtitle)
            .foregroundStyle(.secondary)
            .help(subtitle)
        }

        ForEach(section.controls) { control in
          ControlRenderer(
            control: control,
            localizationLabels: localizationLabels,
            value: binding(for: control),
            checkedIDs: checkedBinding(for: control),
            fieldValues: fieldValues,
            checkedOptions: checkedOptions,
            allFieldValues: $fieldValues,
            configValues: $configValues,
            configFilePaths: $configFilePaths,
            bundleRootURL: bundleRootURL,
            runAction: runAction,
            saveConfig: saveConfig,
            loadConfig: loadConfig,
            persistConfigFilePath: persistConfigFilePath,
            fieldValueChanged: fieldValueChanged,
            checkedOptionsChanged: checkedOptionsChanged,
            configSettingChanged: configSettingChanged
          )
        }

        if !section.actions.isEmpty {
          if hasContentBeforeActions {
            Divider()
          }
          if section.dataSource != nil && sectionValues.isEmpty && dataSourceError == nil {
            HStack(spacing: 8) {
              ProgressView()
                .controlSize(.small)
              Text("Loading...")
                .foregroundStyle(.secondary)
            }
          }
          ActionRow(actions: section.actions, context: commandContext()) { action in
            runAction(action, commandContext())
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .bottomLeading) {
        if let dataSourceError {
          Text(dataSourceError)
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.top, 4)
        }
      }
      .task(id: dataSourceTaskID) {
        await loadDataSourceIfNeeded(clearExistingValues: true)
      }
      .onChange(of: terminal.commandCompletionSerial) {
        refreshDataSourceAfterSectionActionIfNeeded()
      }
    } label: {
      if let title = section.title {
        IconTitleLabel(
          title: title,
          iconName: section.iconName,
          iconEmoji: section.iconEmoji,
          defaultSystemImage: "rectangle.3.group")
      }
    }
  }

  private var hasContentBeforeActions: Bool {
    section.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      || !section.controls.isEmpty
  }

  private var dataSourceTaskID: String {
    guard let dataSource = section.dataSource else { return "" }
    return DataSourceRunner.signature(
      dataSource: dataSource,
      rootURL: bundleRootURL,
      context: dataSourceContext())
  }

  private func dataSourceContext() -> CommandRenderContext {
    CommandRenderContext(
      fieldValues: fieldValues,
      checkedOptions: checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configValues.merging(fieldValues) { _, fieldValue in fieldValue },
      bundleRootPath: bundleRootURL?.path
    )
  }

  private func loadDataSourceIfNeeded(clearExistingValues: Bool) async {
    guard let dataSource = section.dataSource, let bundleRootURL else { return }
    if clearExistingValues {
      sectionValues = [:]
    }
    dataSourceError = nil
    do {
      let payload = try await DataSourceRunner.load(
        dataSource: dataSource,
        rootURL: bundleRootURL,
        context: dataSourceContext())
      sectionValues = payload.values ?? [:]
      dataSourceError = nil
    } catch {
      dataSourceError =
        "Could not load \(section.title ?? section.id): \(error.localizedDescription)"
    }
  }

  private func refreshDataSourceAfterSectionActionIfNeeded() {
    guard section.dataSource != nil, let completedCommand = terminal.lastCompletedCommand else {
      return
    }
    let context = commandContext()
    let sectionCommands = section.actions.map { action in
      action.command.displayCommand(resolving: context)
    }
    guard sectionCommands.contains(completedCommand) else { return }
    Task {
      await loadDataSourceIfNeeded(clearExistingValues: false)
    }
  }

  private func binding(for control: ControlSpec) -> Binding<String> {
    Binding(
      get: { fieldValues[control.id, default: control.value ?? ""] },
      set: { fieldValueChanged($0, control) }
    )
  }

  private func checkedBinding(for control: ControlSpec) -> Binding<Set<String>> {
    Binding(
      get: {
        checkedOptions[control.id, default: Set(control.options.filter(\.selected).map(\.id))]
      },
      set: { checkedOptionsChanged($0, control) }
    )
  }

  private func commandContext(rowValues: [String: String] = [:]) -> CommandRenderContext {
    CommandRenderContext(
      fieldValues: fieldValues.merging(sectionValues) { fieldValue, _ in fieldValue },
      checkedOptions: checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configValues.merging(fieldValues) { _, fieldValue in fieldValue }
        .merging(sectionValues) { configValue, _ in configValue },
      rowValues: rowValues,
      bundleRootPath: bundleRootURL?.path
    )
  }
}

private struct ControlRenderer: View {
  @EnvironmentObject private var terminal: TerminalLogStore
  let control: ControlSpec
  let localizationLabels: BundleLocalizationLabels
  @Binding var value: String
  @Binding var checkedIDs: Set<String>
  let fieldValues: [String: String]
  let checkedOptions: [String: Set<String>]
  @Binding var allFieldValues: [String: String]
  @Binding var configValues: [String: String]
  @Binding var configFilePaths: [String: String]
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
  var saveConfig: (ControlSpec) -> Void
  var loadConfig: (ControlSpec) -> Void
  var persistConfigFilePath: (String, ControlSpec) -> Void
  var fieldValueChanged: (String, ControlSpec) -> Void
  var checkedOptionsChanged: (Set<String>, ControlSpec) -> Void
  var configSettingChanged: (String, ConfigSettingSpec, ControlSpec) -> Void
  @State private var dynamicData = DynamicControlData()
  @State private var dataSourceError: String?
  @State private var isRefreshingDataSource = false

  var body: some View {
    let renderedControl = control.applying(dynamicData)
    Group {
      switch renderedControl.kind {
      case .text:
        labeledControl(renderedControl) {
          TextField(renderedControl.placeholder ?? "", text: $value)
        }
      case .path:
        labeledControl(renderedControl) {
          HStack {
            TextField(renderedControl.placeholder ?? "", text: $value)
            PathPickerButton(
              path: $value,
              labels: localizationLabels,
              rootURL: bundleRootURL)
          }
        }
      case .dropdown:
        labeledControl(renderedControl) {
          Picker("", selection: $value) {
            ForEach(renderedControl.options) { option in
              Text(option.title).tag(option.id)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      case .toggle:
        labeledControl(renderedControl) {
          Toggle(
            "", isOn: Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" })
          )
          .labelsHidden()
        }
      case .checkboxGroup:
        if renderedControl.options.count == 1, let option = renderedControl.options.first {
          labeledControl(renderedControl) {
            checkbox(for: option)
          }
        } else {
          VStack(alignment: .leading, spacing: 10) {
            label(for: renderedControl)
            LazyVGrid(
              columns: [GridItem(.adaptive(minimum: 240), alignment: .leading)], spacing: 8
            ) {
              ForEach(renderedControl.options) { option in
                checkbox(for: option)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .help(renderedControl.tooltip ?? "")
        }
      case .infoGrid:
        VStack(alignment: .leading, spacing: 10) {
          label(for: renderedControl)
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 280), alignment: .leading)], spacing: 8
          ) {
            ForEach(renderedControl.options) { option in
              Text(option.title)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
        }
        .help(renderedControl.tooltip ?? "")
      case .libraryList:
        if control.dataSource != nil && dynamicData.rows == nil {
          LibraryListLoadingControl(
            control: control,
            localizationLabels: localizationLabels,
            isLoading: dataSourceError == nil,
            errorMessage: dataSourceError
          ) {
            Task {
              await loadDataSourceIfNeeded(clearExistingData: true)
            }
          }
        } else {
          LibraryListControl(
            control: renderedControl,
            localizationLabels: localizationLabels,
            fieldValues: fieldValues,
            checkedOptions: checkedOptions,
            configValues: configValues,
            bundleRootURL: bundleRootURL,
            isRefreshing: isRefreshingDataSource,
            dataSourceError: dataSourceError,
            retryDataSource: {
              Task {
                await loadDataSourceIfNeeded(clearExistingData: true)
              }
            },
            runAction: runAction
          )
        }
      case .configEditor:
        ConfigEditorControl(
          control: renderedControl,
          localizationLabels: localizationLabels,
          fieldValues: $allFieldValues,
          configValues: $configValues,
          configFilePaths: $configFilePaths,
          bundleRootURL: bundleRootURL,
          loadConfig: loadConfig,
          persistConfigFilePath: persistConfigFilePath,
          configSettingChanged: configSettingChanged
        )
      }
    }
    .overlay(alignment: .bottomLeading) {
      if let dataSourceError, renderedControl.kind != .libraryList {
        Text(dataSourceError)
          .font(.caption)
          .foregroundStyle(.orange)
          .padding(.top, 4)
      }
    }
    .task(id: dataSourceTaskID) {
      await loadDataSourceIfNeeded(clearExistingData: true)
    }
    .onChange(of: terminal.commandCompletionSerial) {
      refreshDataSourceAfterControlActionIfNeeded()
    }
  }

  private func label(for control: ControlSpec) -> some View {
    InfoLabel(text: control.label, tooltip: control.tooltip, font: .headline)
  }

  private func labeledControl<Content: View>(
    _ control: ControlSpec,
    @ViewBuilder content: () -> Content
  ) -> some View {
    LeadingFormRow {
      label(for: control)
    } content: {
      content()
    }
    .help(control.tooltip ?? "")
  }

  private var dataSourceTaskID: String {
    guard let dataSource = control.dataSource else { return "" }
    return DataSourceRunner.signature(
      dataSource: dataSource,
      rootURL: bundleRootURL,
      context: dataSourceContext)
  }

  private var dataSourceContext: CommandRenderContext {
    CommandRenderContext(
      fieldValues: allFieldValues,
      checkedOptions: checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configValues.merging(allFieldValues) { _, fieldValue in fieldValue },
      bundleRootPath: bundleRootURL?.path)
  }

  private func loadDataSourceIfNeeded(clearExistingData: Bool) async {
    guard let dataSource = control.dataSource, let bundleRootURL else { return }
    if clearExistingData {
      dynamicData = DynamicControlData()
    } else {
      isRefreshingDataSource = true
    }
    dataSourceError = nil
    defer {
      isRefreshingDataSource = false
    }
    do {
      let payload = try await DataSourceRunner.load(
        dataSource: dataSource,
        rootURL: bundleRootURL,
        context: dataSourceContext)
      dynamicData = DynamicControlData(payload: payload)
      selectDefaultOptionIfNeeded(payload.options)
      dataSourceError = nil
    } catch {
      dataSourceError = "Could not load \(control.label): \(error.localizedDescription)"
    }
  }

  private func refreshDataSourceAfterControlActionIfNeeded() {
    guard control.dataSource != nil, let completedCommand = terminal.lastCompletedCommand else {
      return
    }
    let renderedControl = control.applying(dynamicData)
    guard renderedControl.kind == .libraryList else { return }

    let controlCommands = renderedControl.hydratedRows.flatMap { row in
      let context = commandContext(for: row)
      return renderedControl.rowActions
        .filter { $0.isVisible(resolving: context) }
        .map { $0.command.displayCommand(resolving: context) }
    }
    guard controlCommands.contains(completedCommand) else { return }

    Task {
      await loadDataSourceIfNeeded(clearExistingData: false)
    }
  }

  private func commandContext(for row: ListRowSpec) -> CommandRenderContext {
    var rowValues = row.values
    rowValues["id"] = row.id
    rowValues["title"] = row.title ?? row.id
    if let status = row.status {
      rowValues["status"] = status
    }
    return CommandRenderContext(
      fieldValues: fieldValues,
      checkedOptions: checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configValues,
      rowValues: rowValues,
      bundleRootPath: bundleRootURL?.path
    )
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

  private func checkbox(for option: ControlOption) -> some View {
    let toggle = Toggle(
      option.title,
      isOn: Binding(
        get: { checkedIDs.contains(option.id) },
        set: { isSelected in
          if isSelected {
            checkedIDs.insert(option.id)
          } else {
            checkedIDs.remove(option.id)
          }
        }
      )
    )
    .frame(maxWidth: .infinity, alignment: .leading)
    #if os(macOS)
      return toggle.toggleStyle(.checkbox)
    #else
      return toggle
    #endif
  }
}

private struct LibraryListControl: View {
  let control: ControlSpec
  let localizationLabels: BundleLocalizationLabels
  let fieldValues: [String: String]
  let checkedOptions: [String: Set<String>]
  let configValues: [String: String]
  let bundleRootURL: URL?
  var isRefreshing = false
  var dataSourceError: String?
  var retryDataSource: () -> Void = {}
  var runAction: (ActionSpec, CommandRenderContext) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        InfoLabel(text: control.label, tooltip: control.tooltip, font: .headline)
        if isRefreshing {
          ProgressView()
            .controlSize(.small)
          Text(localizationLabels.refreshingTitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      let rows = control.hydratedRows
      if rows.isEmpty {
        Text(emptyMessage)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
          .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      } else {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
          GridRow {
            ForEach(control.columns) { column in
              Text(column.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            if !control.rowActions.isEmpty {
              Text(localizationLabels.actionsColumnTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
          }

          Divider()
            .gridCellColumns(control.columns.count + (control.rowActions.isEmpty ? 0 : 1))

          ForEach(rows) { row in
            GridRow {
              ForEach(control.columns) { column in
                VStack(alignment: .leading, spacing: 2) {
                  Text(displayValue(for: column, row: row))
                    .font(column.id == "name" ? .body.weight(.medium) : .body)
                  if column.id == "name", row.status != nil || !row.tags.isEmpty {
                    HStack(spacing: 4) {
                      if let status = row.status {
                        TagPill(
                          tag: TagSpec(
                            id: "status",
                            title: localizedStatus(status),
                            style: tagStyle(for: status)))
                      }
                      ForEach(row.tags) { tag in
                        TagPill(tag: localizedTag(tag))
                      }
                    }
                  }
                }
                .help(row.tooltip ?? "")
              }

              if !control.rowActions.isEmpty {
                HStack(spacing: 8) {
                  let context = commandContext(for: row)
                  ForEach(visibleRowActions(for: row, context: context)) { action in
                    ActionButton(action: action) {
                      runAction(action, context)
                    }
                    .environment(\.commandRenderContext, context)
                  }
                }
              }
            }
          }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      }

      if let dataSourceError {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(.orange)
          Text(dataSourceError)
            .font(.caption)
            .foregroundStyle(.secondary)
          Button(localizationLabels.retryButtonTitle, action: retryDataSource)
            .buttonStyle(.borderless)
            .font(.caption)
        }
      }
    }
    .help(control.tooltip ?? "")
  }

  private var emptyMessage: String {
    if control.dataSource != nil {
      return "No library items were found for the selected reference library."
    }
    return "No library items are defined."
  }

  private func displayValue(for column: ListColumnSpec, row: ListRowSpec) -> String {
    if column.id == "name" {
      return row.title ?? row.values[column.id] ?? row.id
    }
    if column.id == "status" {
      if let status = row.status {
        return localizedStatus(status)
      }
      return row.values[column.id] ?? ""
    }
    return row.values[column.id] ?? ""
  }

  private func localizedStatus(_ status: String) -> String {
    localizationLabels.libraryStatusLabels[status.lowercased()] ?? status
  }

  private func localizedTag(_ tag: TagSpec) -> TagSpec {
    var tag = tag
    tag.title =
      localizationLabels.libraryTagLabels[tag.id]
      ?? localizationLabels.libraryTagLabels[tag.title.lowercased()]
      ?? tag.title
    return tag
  }

  private func commandContext(for row: ListRowSpec) -> CommandRenderContext {
    var rowValues = row.values
    rowValues["id"] = row.id
    rowValues["title"] = row.title ?? row.id
    if let status = row.status {
      rowValues["status"] = status
    }
    return CommandRenderContext(
      fieldValues: fieldValues,
      checkedOptions: checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configValues,
      rowValues: rowValues,
      bundleRootPath: bundleRootURL?.path
    )
  }

  private func visibleRowActions(for row: ListRowSpec, context: CommandRenderContext)
    -> [ActionSpec]
  {
    control.rowActions.filter { $0.isVisible(resolving: context) }
  }

  private func tagStyle(for status: String) -> TagStyle {
    switch status.lowercased() {
    case "installed":
      return .success
    case "unindexed", "incomplete":
      return .warning
    case "missing":
      return .secondary
    default:
      return .primary
    }
  }
}

private struct LibraryListLoadingControl: View {
  let control: ControlSpec
  let localizationLabels: BundleLocalizationLabels
  var isLoading: Bool
  var errorMessage: String?
  var retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      InfoLabel(text: control.label, tooltip: control.tooltip, font: .headline)

      if isLoading {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(localizationLabels.loadingTitle)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      } else if let errorMessage {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
              .foregroundStyle(.orange)
            Text(errorMessage)
              .foregroundStyle(.secondary)
          }
          Button(localizationLabels.retryButtonTitle, action: retry)
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      }
    }
    .help(control.tooltip ?? "")
  }
}

private struct TagPill: View {
  let tag: TagSpec

  var body: some View {
    Text(tag.title)
      .font(.caption2.weight(.semibold))
      .textCase(.uppercase)
      .foregroundStyle(foregroundStyle)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(backgroundStyle, in: Capsule())
      .overlay {
        Capsule()
          .stroke(foregroundStyle.opacity(0.45), lineWidth: 0.75)
      }
  }

  private var foregroundStyle: Color {
    switch tag.style {
    case .primary:
      return .accentColor
    case .secondary:
      return .secondary
    case .success:
      return .green
    case .warning:
      return .orange
    case .danger:
      return .red
    }
  }

  private var backgroundStyle: Color {
    foregroundStyle.opacity(0.24)
  }
}

private struct ConfigEditorControl: View {
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

private struct ConfigSettingRenderer: View {
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
            Text(option.title).tag(option.id)
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
}

private struct LeadingFormRow<Label: View, Content: View>: View {
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

private struct PathPickerButton: View {
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

private struct ActionRow: View {
  let actions: [ActionSpec]
  let context: CommandRenderContext
  var runAction: (ActionSpec) -> Void

  var body: some View {
    let visibleActions = actions.filter { $0.isVisible(resolving: context) }
    if visibleActions.count == 1, let action = visibleActions.first {
      HStack {
        actionButton(action)
          .fixedSize(horizontal: true, vertical: false)
        Spacer(minLength: 0)
      }
    } else {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)], spacing: 10) {
        ForEach(visibleActions) { action in
          actionButton(action)
        }
      }
    }
  }

  private func actionButton(_ action: ActionSpec) -> some View {
    ActionButton(action: action) {
      runAction(action)
    }
    .environment(\.commandRenderContext, context)
  }
}

private struct ActionButton: View {
  @Environment(\.commandRenderContext) private var context
  @EnvironmentObject private var terminal: TerminalLogStore
  let action: ActionSpec
  var run: () -> Void
  @State private var isConfirming = false
  @State private var confirmationInput = ""

  var body: some View {
    let missingPlaceholders = action.command.missingPlaceholders(resolving: context)
    let displayCommand = action.command.displayCommand(resolving: context)
    let isRunning = terminal.isCommandRunning(displayCommand)
    let disabledReason = action.disabledReason(resolving: context)
    let isActionDisabled = !missingPlaceholders.isEmpty || disabledReason != nil || isRunning
    let help = helpText(missingPlaceholders: missingPlaceholders, disabledReason: disabledReason)
    Button(role: action.role == .destructive ? .destructive : nil) {
      if action.confirm != nil {
        confirmationInput = ""
        isConfirming = true
      } else {
        run()
      }
    } label: {
      if isRunning {
        HStack {
          ProgressView()
            .controlSize(.small)
          if !action.iconOnly {
            Text(action.title)
          }
        }
        .frame(maxWidth: action.iconOnly ? nil : .infinity)
      } else {
        IconTitleLabel(
          title: action.title,
          iconName: action.iconName,
          iconEmoji: action.iconEmoji,
          defaultSystemImage: "play",
          iconOnly: action.iconOnly
        )
        .frame(maxWidth: action.iconOnly ? nil : .infinity)
      }
    }
    .controlSize(.regular)
    .disabled(isActionDisabled)
    .destructiveActionStyle(
      isDestructive: action.role == .destructive, isDisabled: isActionDisabled
    )
    .quickHelp(help)
    .accessibilityLabel(action.title)
    .sheet(isPresented: $isConfirming) {
      if let confirmation = action.confirm {
        ActionConfirmationSheet(
          action: action,
          confirmation: confirmation,
          context: context,
          input: $confirmationInput,
          isPresented: $isConfirming,
          confirm: run)
      }
    }
  }

  private func helpText(missingPlaceholders: [String], disabledReason: String?) -> String {
    if !missingPlaceholders.isEmpty {
      let missing = missingPlaceholders.map(Self.placeholderLabel).joined(separator: ", ")
      if let tooltip = action.tooltip?.nonEmpty {
        return "\(tooltip)\n\nMissing: \(missing)"
      }
      return "Missing: \(missing)"
    }
    if let disabledReason {
      if let tooltip = action.tooltip?.nonEmpty {
        return "\(tooltip)\n\n\(disabledReason)"
      }
      return disabledReason
    }
    return action.tooltip ?? action.command.displayCommand(resolving: context)
  }

  private static func placeholderLabel(_ placeholder: String) -> String {
    let trimmed =
      placeholder
      .replacingOccurrences(of: "row.", with: "")
      .replacingOccurrences(of: "config.", with: "")
    return
      trimmed
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
  }
}

private struct ActionConfirmationSheet: View {
  let action: ActionSpec
  let confirmation: ActionConfirmationSpec
  let context: CommandRenderContext
  @Binding var input: String
  @Binding var isPresented: Bool
  var confirm: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      IconTitleLabel(
        title: resolved(confirmation.title),
        iconName: action.role == .destructive ? "exclamationmark.triangle.fill" : action.iconName,
        iconEmoji: action.iconEmoji,
        defaultSystemImage: "questionmark.circle"
      )
      .font(.title3.weight(.semibold))

      if let message = confirmation.message?.nonEmpty {
        Text(resolved(message))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let requiredText = resolvedRequiredText {
        VStack(alignment: .leading, spacing: 6) {
          Text(resolved(confirmation.prompt ?? "Type \"\(requiredText)\" to confirm."))
            .font(.caption)
            .foregroundStyle(.secondary)
          TextField(requiredText, text: $input)
            .textFieldStyle(.roundedBorder)
        }
      }

      HStack {
        Spacer()
        Button(resolved(confirmation.cancelButtonTitle)) {
          isPresented = false
        }
        Button(
          resolved(confirmation.confirmButtonTitle),
          role: action.role == .destructive ? .destructive : nil
        ) {
          isPresented = false
          confirm()
        }
        .disabled(!canConfirm)
        .destructiveActionStyle(
          isDestructive: action.role == .destructive,
          isDisabled: !canConfirm
        )
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 420)
  }

  private var resolvedRequiredText: String? {
    resolved(confirmation.requiredText).nonEmpty
  }

  private var canConfirm: Bool {
    guard let requiredText = resolvedRequiredText else { return true }
    return input == requiredText
  }

  private func resolved(_ value: String?) -> String? {
    value.map { resolved($0) }
  }

  private func resolved(_ value: String) -> String {
    context.interpolated(value)
  }
}

private struct QuickHelpModifier: ViewModifier {
  let text: String
  @State private var isHovering = false
  @State private var isPresented = false
  @State private var showTask: Task<Void, Never>?

  func body(content: Content) -> some View {
    #if os(macOS)
      content
        .onHover { hovering in
          isHovering = hovering
          showTask?.cancel()
          if hovering {
            showTask = Task {
              try? await Task.sleep(nanoseconds: 180_000_000)
              guard !Task.isCancelled else { return }
              await MainActor.run {
                if isHovering {
                  isPresented = true
                }
              }
            }
          } else {
            isPresented = false
          }
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
          InfoPopoverContent(text: text)
        }
        .onDisappear {
          showTask?.cancel()
          showTask = nil
        }
    #else
      content
    #endif
  }
}

private extension View {
  func quickHelp(_ text: String) -> some View {
    modifier(QuickHelpModifier(text: text))
  }

  @ViewBuilder
  func destructiveActionStyle(isDestructive: Bool, isDisabled: Bool) -> some View {
    if isDestructive && !isDisabled {
      self
        .foregroundStyle(.red)
        .tint(.red)
    } else {
      self
    }
  }
}

private struct InfoButton: View {
  let text: String
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Image(systemName: "info.circle")
        .foregroundStyle(.secondary)
    }
    .buttonStyle(.borderless)
    .help(text)
    .popover(isPresented: $isPresented, arrowEdge: .top) {
      InfoPopoverContent(text: text)
    }
  }
}

private struct InfoLabel: View {
  let text: String
  var tooltip: String?
  var font: Font?
  @State private var isPresented = false

  var body: some View {
    HStack(spacing: 6) {
      labelText
      if let tooltip {
        InfoButton(text: tooltip)
      }
    }
    .popover(isPresented: $isPresented, arrowEdge: .top) {
      InfoPopoverContent(text: tooltip ?? "")
    }
  }

  @ViewBuilder private var labelText: some View {
    if let tooltip {
      Text(text)
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
        .onTapGesture {
          isPresented.toggle()
        }
        .quickHelp(tooltip)
    } else {
      Text(text)
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct InfoPopoverContent: View {
  let text: String
  private var preferredWidth: CGFloat {
    min(max(CGFloat(text.count) * 5.8, 280), 640)
  }

  var body: some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.primary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(14)
      .frame(width: preferredWidth, alignment: .leading)
  }
}

private struct CommandRenderContext: Sendable {
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
    default:
      return nil
    }
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

private extension EnvironmentValues {
  var commandRenderContext: CommandRenderContext {
    get { self[CommandRenderContextKey.self] }
    set { self[CommandRenderContextKey.self] = newValue }
  }
}

private struct RenderedCommand: Sendable {
  var executable: String
  var arguments: [String]

  var displayCommand: String {
    ([executable] + arguments).map(Self.shellQuoted).joined(separator: " ")
  }

  private static func shellQuoted(_ value: String) -> String {
    guard !value.isEmpty, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
      !value.contains("'")
    else {
      return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
    return value
  }
}

private extension CommandSpec {
  func renderedCommand(resolving context: CommandRenderContext) -> RenderedCommand {
    let renderedOptionalArguments = optionalArguments.flatMap { group -> [String] in
      guard requiredPlaceholders(in: group, resolving: context).isEmpty else {
        return []
      }
      return group.map { interpolate($0, context: context) }
    }
    return RenderedCommand(
      executable: interpolate(executable, context: context),
      arguments: arguments.map { interpolate($0, context: context) } + renderedOptionalArguments
    )
  }

  func displayCommand(resolving context: CommandRenderContext) -> String {
    renderedCommand(resolving: context).displayCommand
  }

  func missingPlaceholders(resolving context: CommandRenderContext) -> [String] {
    requiredPlaceholders(in: [executable] + arguments, resolving: context)
  }

  private func requiredPlaceholders(in values: [String], resolving context: CommandRenderContext)
    -> [String]
  {
    var missing: [String] = []
    for placeholder in placeholders(in: values) {
      let value = context.value(for: placeholder)?.trimmingCharacters(in: .whitespacesAndNewlines)
      if value?.isEmpty != false, !missing.contains(placeholder) {
        missing.append(placeholder)
      }
    }
    return missing
  }

  private func interpolate(_ value: String, context: CommandRenderContext) -> String {
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
      result.replaceSubrange(replacementRange, with: context.value(for: placeholder) ?? "")
    }
    return result
  }

  private func placeholders(in values: [String]) -> [String] {
    let pattern = #"\{\{([^}]+)\}\}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return []
    }
    return values.flatMap { value in
      regex.matches(
        in: value,
        range: NSRange(value.startIndex..<value.endIndex, in: value)
      ).compactMap { match in
        guard let range = Range(match.range(at: 1), in: value) else {
          return nil
        }
        return String(value[range]).trimmingCharacters(in: .whitespaces)
      }
    }
  }
}

private extension ActionSpec {
  func isVisible(resolving context: CommandRenderContext) -> Bool {
    visibleWhen.allSatisfy { $0.matches(resolving: context) }
  }

  func disabledReason(resolving context: CommandRenderContext) -> String? {
    guard disabledWhen.contains(where: { $0.matches(resolving: context) }) else {
      return nil
    }
    return disabledTooltip.map { context.interpolated($0) }.nonEmpty
      ?? "This action is not available."
  }
}

private extension ActionConditionSpec {
  func matches(resolving context: CommandRenderContext) -> Bool {
    let value = context.value(for: placeholder) ?? ""
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if let exists {
      let hasValue = !trimmed.isEmpty
      if exists != hasValue {
        return false
      }
    }
    if let equals, trimmed != equals {
      return false
    }
    if let notEquals, trimmed == notEquals {
      return false
    }
    if !inValues.isEmpty && !inValues.contains(trimmed) {
      return false
    }
    if notInValues.contains(trimmed) {
      return false
    }
    return true
  }
}

private struct DynamicControlData: Equatable {
  var options: [ControlOption]?
  var rows: [ListRowSpec]?
  var rowActions: [ActionSpec]?

  init(options: [ControlOption]? = nil, rows: [ListRowSpec]? = nil, rowActions: [ActionSpec]? = nil)
  {
    self.options = options
    self.rows = rows
    self.rowActions = rowActions
  }

  init(payload: DataSourcePayload) {
    self.options = payload.options
    self.rows = payload.rows
    self.rowActions = payload.rowActions
  }
}

private struct DataSourcePayload: Decodable, Equatable, Sendable {
  var options: [ControlOption]?
  var rows: [ListRowSpec]?
  var rowActions: [ActionSpec]?
  var values: [String: String]?

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    options = try container.decodeIfPresent([ControlOption].self, forKey: .options)
    rows =
      try container.decodeIfPresent([ListRowSpec].self, forKey: .rows)
      ?? container.decodeIfPresent([ListRowSpec].self, forKey: .items)
    rowActions =
      try container.decodeIfPresent([ActionSpec].self, forKey: .rowActions)
      ?? container.decodeIfPresent([ActionSpec].self, forKey: .actions)
    values = try container.decodeIfPresent([String: String].self, forKey: .values)
  }

  private enum CodingKeys: String, CodingKey {
    case options
    case rows
    case items
    case rowActions
    case actions
    case values
  }
}

private enum DataSourceRunner {
  private static let timeoutSeconds: UInt64 = 15
  private static let maxStandardOutputBytes = 1_048_576
  private static let maxStandardErrorBytes = 65_536

  static func signature(
    dataSource: ScriptDataSourceSpec,
    rootURL: URL?,
    context: CommandRenderContext
  ) -> String {
    [
      dataSource.path,
      dataSource.arguments.joined(separator: "\u{1f}"),
      dataSource.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        .joined(separator: "\u{1e}"),
      dataSource.workingDirectory ?? "",
      rootURL?.path ?? "",
      context.fieldValues.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        .joined(separator: "\u{1d}"),
      context.checkedOptions.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        .joined(separator: "\u{1c}"),
      context.configValues.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        .joined(separator: "\u{1b}"),
    ].joined(separator: "\u{1a}")
  }

  static func load(
    dataSource: ScriptDataSourceSpec,
    rootURL: URL,
    context: CommandRenderContext
  ) async throws -> DataSourcePayload {
    #if os(macOS)
      return try await Task.detached {
        let output = try await run(dataSource: dataSource, rootURL: rootURL, context: context)
        do {
          return try JSONDecoder().decode(DataSourcePayload.self, from: output)
        } catch {
          throw DataSourceError.invalidJSON(
            path: dataSource.path,
            message: error.localizedDescription,
            preview: outputPreview(output))
        }
      }.value
    #else
      throw DataSourceError.unsupportedPlatform
    #endif
  }

  #if os(macOS)
    private static func run(
      dataSource: ScriptDataSourceSpec,
      rootURL: URL,
      context: CommandRenderContext
    ) async throws -> Data {
      try await withThrowingTaskGroup(of: Data.self) { group in
        group.addTask {
          try await runProcess(dataSource: dataSource, rootURL: rootURL, context: context)
        }
        group.addTask {
          try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
          throw DataSourceError.timedOut(path: dataSource.path, seconds: timeoutSeconds)
        }
        defer { group.cancelAll() }
        guard let output = try await group.next() else {
          throw CancellationError()
        }
        return output
      }
    }

    private static func runProcess(
      dataSource: ScriptDataSourceSpec,
      rootURL: URL,
      context: CommandRenderContext
    ) async throws -> Data {
      let executable = try resolve(dataSource.path, rootURL: rootURL)
      let workingDirectory =
        try dataSource.workingDirectory.map { try resolve($0, rootURL: rootURL) } ?? rootURL
      let processBox = DataSourceProcessBox()

      return try await withTaskCancellationHandler {
        let output = try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Data, Error>) in
          let process = Process()
          process.executableURL = executable
          process.arguments = dataSource.arguments.map { interpolate($0, context: context) }
          process.currentDirectoryURL = workingDirectory

          var environment = ProcessInfo.processInfo.environment
          environment["GUI_FOR_CLI_BUNDLE_ROOT"] = rootURL.path
          environment["GUI_FOR_CLI_BUNDLE_WORKSPACE"] = rootURL.path
          environment["GUI_FOR_CLI_DATA_SOURCE"] = "1"
          for (key, value) in context.fieldValues {
            environment["GUI_FOR_CLI_FIELD_\(environmentKey(key))"] = value
          }
          for (key, value) in context.configValues {
            environment["GUI_FOR_CLI_CONFIG_\(environmentKey(key))"] = value
          }
          for (key, value) in dataSource.environment {
            environment[key] = interpolate(value, context: context)
          }
          process.environment = environment

          let stdout = Pipe()
          let stderr = Pipe()
          let stdoutBuffer = DataSourceOutputBuffer(maxBytes: maxStandardOutputBytes)
          let stderrBuffer = DataSourceOutputBuffer(maxBytes: maxStandardErrorBytes)
          process.standardOutput = stdout
          process.standardError = stderr

          stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
          }
          stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
          }

          process.terminationHandler = { finishedProcess in
            stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
            stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            processBox.clear(finishedProcess)

            if processBox.wasCancelled {
              continuation.resume(throwing: CancellationError())
              return
            }

            let output = stdoutBuffer.snapshot()
            let errorOutput = stderrBuffer.snapshot()
            guard finishedProcess.terminationStatus == 0 else {
              continuation.resume(
                throwing: DataSourceError.scriptFailed(
                  path: dataSource.path,
                  exitCode: finishedProcess.terminationStatus,
                  message: failureMessage(
                    stderr: errorOutput.data,
                    stderrTruncated: errorOutput.truncated)))
              return
            }
            continuation.resume(returning: output.data)
          }

          processBox.set(process)
          do {
            try process.run()
          } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            processBox.clear(process)
            continuation.resume(
              throwing: DataSourceError.launchFailed(
                path: dataSource.path,
                message: error.localizedDescription))
          }
        }
        if Task.isCancelled {
          throw CancellationError()
        }
        return output
      } onCancel: {
        processBox.terminate()
      }
    }

    private static func failureMessage(stderr: Data, stderrTruncated: Bool) -> String {
      let message =
        String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        .nonEmpty
        ?? "Script failed without writing stderr."
      return stderrTruncated ? "\(message)\n(stderr truncated)" : message
    }
  #endif

  private static func outputPreview(_ data: Data) -> String {
    let text = String(data: data.prefix(512), encoding: .utf8) ?? "<non-UTF-8 output>"
    if data.count > 512 {
      return "\(text)\n(output truncated)"
    }
    return text
  }

  #if os(macOS)
    private final class DataSourceProcessBox: @unchecked Sendable {
      private let lock = NSLock()
      private var process: Process?
      private var cancelled = false

      var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
      }

      func set(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = cancelled
        lock.unlock()
        if shouldTerminate {
          process.terminate()
        }
      }

      func clear(_ process: Process) {
        lock.lock()
        if self.process === process {
          self.process = nil
        }
        lock.unlock()
      }

      func terminate() {
        lock.lock()
        cancelled = true
        let process = process
        lock.unlock()
        process?.terminate()
      }
    }

    private final class DataSourceOutputBuffer: @unchecked Sendable {
      private let maxBytes: Int
      private let lock = NSLock()
      private var data = Data()
      private var truncated = false

      init(maxBytes: Int) {
        self.maxBytes = maxBytes
      }

      func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        let remaining = maxBytes - data.count
        if remaining > 0 {
          data.append(contentsOf: chunk.prefix(remaining))
        }
        if chunk.count > max(remaining, 0) {
          truncated = true
        }
        lock.unlock()
      }

      func snapshot() -> (data: Data, truncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, truncated)
      }
    }
  #endif

  #if os(macOS)
    private static func resolve(_ path: String, rootURL: URL) throws -> URL {
      let expanded = BundlePathResolver.expand(path, rootURL: rootURL)
      guard !(expanded as NSString).isAbsolutePath else {
        throw DataSourceError.invalidPath(path)
      }
      let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
      let candidate =
        rootURL
        .appendingPathComponent(expanded)
        .standardizedFileURL
        .resolvingSymlinksInPath()
      guard isContained(candidate, in: root) else {
        throw DataSourceError.invalidPath(path)
      }
      return candidate
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
      let rootPath = root.path
      let candidatePath = candidate.path
      return candidatePath == rootPath || candidatePath.hasPrefix("\(rootPath)/")
    }
  #else
    private static func resolve(_ path: String, rootURL: URL) throws -> URL {
      let expanded = BundlePathResolver.expand(path, rootURL: rootURL)
      if (expanded as NSString).isAbsolutePath {
        return URL(fileURLWithPath: expanded)
      }
      return rootURL.appendingPathComponent(expanded)
    }
  #endif

  private static func interpolate(_ value: String, context: CommandRenderContext) -> String {
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
      result.replaceSubrange(replacementRange, with: context.value(for: placeholder) ?? "")
    }
    return result
  }

  private static func environmentKey(_ value: String) -> String {
    value.map { character in
      if character.isLetter || character.isNumber {
        return String(character).uppercased()
      }
      return "_"
    }.joined()
  }
}

private enum DataSourceError: LocalizedError, Sendable {
  case scriptFailed(path: String, exitCode: Int32, message: String)
  case launchFailed(path: String, message: String)
  case invalidJSON(path: String, message: String, preview: String)
  case invalidPath(String)
  case timedOut(path: String, seconds: UInt64)
  case unsupportedPlatform

  var errorDescription: String? {
    switch self {
    case .scriptFailed(let path, let exitCode, let message):
      return "\(path) exited with code \(exitCode): \(message)"
    case .launchFailed(let path, let message):
      return "Could not launch \(path): \(message)"
    case .invalidJSON(let path, let message, let preview):
      return "Could not decode JSON from \(path): \(message). Output: \(preview)"
    case .invalidPath(let path):
      return "Data source path must stay inside the bundle: \(path)"
    case .timedOut(let path, let seconds):
      return "\(path) did not finish within \(seconds) seconds."
    case .unsupportedPlatform:
      return "Script-backed data sources are only available on macOS."
    }
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

private extension ControlSpec {
  func applying(_ dynamicData: DynamicControlData) -> ControlSpec {
    var control = self
    if let options = dynamicData.options {
      control.options = options
    }
    if let rows = dynamicData.rows {
      control.rows = rows
      control.items = []
    }
    if let rowActions = dynamicData.rowActions {
      control.rowActions = rowActions
    }
    return control
  }
}

private struct TerminalPane: View {
  @ObservedObject var store: TerminalLogStore
  let labels: BundleLocalizationLabels
  let textDirection: LayoutDirection

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "terminal")
          .font(.headline)
          .accessibilityLabel(labels.terminalCommandOutputLabel)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(store.tabs) { tab in
              TerminalTabButton(
                tab: tab,
                isSelected: store.selectedTabID == tab.id,
                close: { store.closeTab(tab.id) },
                select: { store.selectedTabID = tab.id }
              )
            }
          }
          .padding(.vertical, 2)
        }

        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

      Divider()

      ScrollViewReader { proxy in
        ScrollView {
          Text(store.selectedTab?.lines.joined(separator: "\n") ?? "")
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: terminalTextAlignment)
            .textSelection(.enabled)
            .padding(12)
            .environment(\.layoutDirection, textDirection)

          Color.clear
            .frame(height: 1)
            .id(Self.bottomAnchorID)
        }
        .onChange(of: store.selectedTabID) { _, _ in
          proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
        .onChange(of: store.selectedLineCount) { _, _ in
          proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
      }
      .background(.regularMaterial)
    }
  }

  private static let bottomAnchorID = "terminal-bottom"

  private var terminalTextAlignment: Alignment {
    textDirection == .rightToLeft ? .trailing : .leading
  }
}

private struct TerminalTabButton: View {
  var tab: TerminalTab
  var isSelected: Bool
  var close: () -> Void
  var select: () -> Void
  @State private var showsStatusExplanation = false

  var body: some View {
    HStack(spacing: 4) {
      Button {
        select()
        if tab.status != nil {
          showsStatusExplanation = true
        }
      } label: {
        HStack(spacing: 4) {
          if tab.isRunning {
            ProgressView()
              .controlSize(.small)
          } else if let status = tab.status {
            Image(systemName: status.symbolName)
              .foregroundStyle(status.tint)
              .accessibilityLabel(status.accessibilityLabel)
          }
          Text(tab.title)
            .lineLimit(1)
        }
      }
      .buttonStyle(.plain)
      .popover(isPresented: $showsStatusExplanation, arrowEdge: .bottom) {
        if let status = tab.status {
          VStack(alignment: .leading, spacing: 8) {
            Label(status.title, systemImage: status.symbolName)
              .font(.headline)
              .foregroundStyle(status.tint)
            Text(status.blurb)
              .font(.callout)
              .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text(status.detail)
              .font(.system(.callout, design: .monospaced))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(14)
          .frame(width: 320, alignment: .leading)
        }
      }

      if !tab.isMain {
        Button(action: close) {
          Image(systemName: "xmark")
            .font(.caption2.weight(.semibold))
            .padding(3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.isRunning ? "Cancel \(tab.title)" : "Close \(tab.title)")
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(backgroundColor)
    .clipShape(Capsule())
    .overlay {
      Capsule()
        .strokeBorder(borderColor, lineWidth: tab.status == nil ? 0 : 1)
    }
  }

  private var backgroundColor: Color {
    if let status = tab.status {
      return status.tint.opacity(isSelected ? 0.28 : 0.16)
    }
    return isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)
  }

  private var borderColor: Color {
    tab.status?.tint.opacity(isSelected ? 0.65 : 0.35) ?? .clear
  }
}

@MainActor
private final class TerminalLogStore: ObservableObject {
  @Published var tabs: [TerminalTab]
  @Published var selectedTabID: UUID?
  @Published private var runningCommandCounts: [String: Int] = [:]
  @Published private(set) var commandCompletionSerial = 0
  private(set) var lastCompletedCommand: String?

  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var exitCodeReference: [Int32: ExitCodeReferenceEntry]
  #if os(macOS)
    private var processes: [UUID: Process] = [:]
  #endif

  init(
    exitCodeReference: [ExitCodeReferenceEntry] = [],
    localizationLabels: BundleLocalizationLabels = BundleLocalizationLabels()
  ) {
    tabs = [
      TerminalTab(
        title: localizationLabels.terminalMainTabTitle, command: "main",
        lines: [
          "[08:00:00] GUI for CLI started.",
          "[08:00:00] Loaded sample bundle: WGS Extract.",
          "[08:00:00] Bundle setup can check PATH tools, bundled scripts, and Homebrew packages.",
        ])
    ]
    self.exitCodeReference = Dictionary(
      exitCodeReference.map { ($0.code, $0) },
      uniquingKeysWith: { first, _ in first })
    selectedTabID = tabs.first?.id
  }

  func updateExitCodeReference(_ entries: [ExitCodeReferenceEntry]) {
    exitCodeReference = Dictionary(
      entries.map { ($0.code, $0) },
      uniquingKeysWith: { first, _ in first })
  }

  func updateLocalizationLabels(_ labels: BundleLocalizationLabels) {
    guard !tabs.isEmpty else { return }
    tabs[0].title = labels.terminalMainTabTitle
  }

  var selectedTab: TerminalTab? {
    tabs.first { $0.id == selectedTabID }
  }

  var selectedLineCount: Int {
    selectedTab?.lines.count ?? 0
  }

  func isCommandRunning(_ command: String) -> Bool {
    runningCommandCounts[command, default: 0] > 0
  }

  func appendToMain(_ line: String) {
    guard let mainID = tabs.first?.id else { return }
    append(line, to: mainID)
  }

  func replaceMain(_ lines: [String]) {
    guard !tabs.isEmpty else { return }
    tabs[0].lines = lines
    selectedTabID = tabs[0].id
  }

  func start(title: String, command: RenderedCommand, workingDirectory: URL?) {
    let tab = TerminalTab(
      title: title, command: command.displayCommand,
      lines: [
        "$ \(command.displayCommand)",
        "[queued] Preparing command environment...",
      ],
      isRunning: true)
    tabs.append(tab)
    selectedTabID = tab.id
    incrementRunningCommand(command.displayCommand)

    tasks[tab.id] = Task { @MainActor [weak self] in
      await self?.runCommand(tabID: tab.id, command: command, workingDirectory: workingDirectory)
    }
  }

  func startSetup(_ commands: [SetupCommand]) {
    guard !commands.isEmpty else {
      appendToMain("[setup] Bundle has no setup steps.")
      return
    }

    let tab = TerminalTab(
      title: "Setup",
      command: "bundle setup",
      lines: commands.flatMap { command in
        [
          "==> \(command.label)",
          "$ \(command.displayCommand)",
        ]
      },
      isRunning: true
    )
    tabs.append(tab)
    selectedTabID = tab.id

    tasks[tab.id] = Task { @MainActor [weak self] in
      await self?.runSetup(tabID: tab.id, commands: commands)
    }
  }

  func closeTab(_ tabID: UUID) {
    guard tabs.first?.id != tabID else {
      return
    }

    tasks[tabID]?.cancel()
    tasks[tabID] = nil
    #if os(macOS)
      processes[tabID]?.terminate()
      processes[tabID] = nil
    #endif
    tabs.removeAll { $0.id == tabID }
    if selectedTabID == tabID {
      selectedTabID = tabs.first?.id
    }
  }

  private func runCommand(tabID: UUID, command: RenderedCommand, workingDirectory: URL?) async {
    defer {
      setTabRunning(false, tabID: tabID)
      decrementRunningCommand(command.displayCommand)
      publishCommandCompletion(command.displayCommand)
    }
    #if os(macOS)
      do {
        append("[running] \(command.displayCommand)", to: tabID)
        let exitStatus = try await runProcess(
          tabID: tabID,
          command: command,
          workingDirectory: workingDirectory)
        if Task.isCancelled {
          append("[cancelled] \(command.displayCommand)", to: tabID)
          setTabStatus(cancelledStatus(command: command.displayCommand), tabID: tabID)
        } else if exitStatus == 0 {
          append("[done] exit code 0", to: tabID)
        } else {
          append("[exit \(exitStatus)] \(command.displayCommand)", to: tabID)
          setTabStatus(
            exitFailureStatus(exitCode: exitStatus, command: command.displayCommand), tabID: tabID)
        }
      } catch is CancellationError {
        append("[cancelled] \(command.displayCommand)", to: tabID)
        setTabStatus(cancelledStatus(command: command.displayCommand), tabID: tabID)
      } catch {
        append("[error] \(error.localizedDescription)", to: tabID)
        setTabStatus(
          .processError(command: command.displayCommand, message: error.localizedDescription),
          tabID: tabID)
      }
      processes[tabID] = nil
      tasks[tabID] = nil
    #else
      append("[error] Command execution is only available on macOS.", to: tabID)
      tasks[tabID] = nil
    #endif
  }

  private func runSetup(tabID: UUID, commands: [SetupCommand]) async {
    defer {
      setTabRunning(false, tabID: tabID)
    }
    let runner = SetupCommandRunner()
    var warningStatus: TerminalTabStatus?
    for command in commands {
      if Task.isCancelled {
        append("[cancelled] setup stopped", to: tabID)
        setTabStatus(cancelledStatus(command: "bundle setup"), tabID: tabID)
        break
      }

      do {
        let result = try await Task.detached {
          try runner.run(command)
        }.value
        if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          append(result.output.trimmingCharacters(in: .newlines), to: tabID)
        }
        if result.exitStatus != 0 {
          append("[exit \(result.exitStatus)] \(command.label)", to: tabID)
          let status = exitFailureStatus(
            exitCode: result.exitStatus,
            command: command.label,
            severity: command.optional ? .warning : .error)
          if command.optional {
            warningStatus = warningStatus ?? status
          } else {
            setTabStatus(status, tabID: tabID)
            break
          }
        } else {
          append("[ok] \(command.label)", to: tabID)
        }
      } catch {
        append("[error] \(command.label): \(error.localizedDescription)", to: tabID)
        let status = TerminalTabStatus.processError(
          command: command.label,
          message: error.localizedDescription,
          severity: command.optional ? .warning : .error)
        if command.optional {
          warningStatus = warningStatus ?? status
        } else {
          setTabStatus(status, tabID: tabID)
          break
        }
      }
    }
    if let warningStatus, tabStatus(for: tabID) == nil {
      setTabStatus(warningStatus, tabID: tabID)
    }
    tasks[tabID] = nil
  }

  private func setTabRunning(_ isRunning: Bool, tabID: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    tabs[index].isRunning = isRunning
  }

  private func setTabStatus(_ status: TerminalTabStatus, tabID: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    tabs[index].status = status
  }

  private func tabStatus(for tabID: UUID) -> TerminalTabStatus? {
    tabs.first { $0.id == tabID }?.status
  }

  private func exitFailureStatus(
    exitCode: Int32,
    command: String,
    severity: TerminalTabStatusSeverity = .error
  ) -> TerminalTabStatus {
    TerminalTabStatus.exitFailure(
      exitCode: exitCode,
      command: command,
      severity: severity,
      reference: exitCodeReference[exitCode])
  }

  private func cancelledStatus(command: String) -> TerminalTabStatus {
    TerminalTabStatus.cancelled(command: command, reference: exitCodeReference[130])
  }

  private func incrementRunningCommand(_ command: String) {
    runningCommandCounts[command, default: 0] += 1
  }

  private func decrementRunningCommand(_ command: String) {
    let count = runningCommandCounts[command, default: 0]
    if count <= 1 {
      runningCommandCounts.removeValue(forKey: command)
    } else {
      runningCommandCounts[command] = count - 1
    }
  }

  private func publishCommandCompletion(_ command: String) {
    lastCompletedCommand = command
    commandCompletionSerial += 1
  }

  private func append(_ line: String, to tabID: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    tabs[index].lines.append(line)
  }

  #if os(macOS)
    private func runProcess(tabID: UUID, command: RenderedCommand, workingDirectory: URL?)
      async throws
      -> Int32
    {
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let process = Process()
          let output = Pipe()

          if command.executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
          } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command.executable] + command.arguments
          }
          process.currentDirectoryURL = workingDirectory
          process.standardOutput = output
          process.standardError = output
          process.environment = commandEnvironment()

          output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
              return
            }
            Task { @MainActor in
              self?.appendProcessOutput(text, to: tabID)
            }
          }

          process.terminationHandler = { [weak self] finishedProcess in
            let remaining = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: remaining, encoding: .utf8)
            let exitStatus = finishedProcess.terminationStatus
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
              if !remaining.isEmpty, let text {
                self?.appendProcessOutput(text, to: tabID)
              }
              continuation.resume(returning: exitStatus)
            }
          }

          processes[tabID] = process
          do {
            try process.run()
          } catch {
            processes[tabID] = nil
            output.fileHandleForReading.readabilityHandler = nil
            continuation.resume(throwing: error)
          }
        }
      } onCancel: {
        Task { @MainActor in
          processes[tabID]?.terminate()
          processes[tabID] = nil
        }
      }
    }

    private func appendProcessOutput(_ output: String, to tabID: UUID) {
      for line in output.split(whereSeparator: \.isNewline) {
        append("[stdout] \(line)", to: tabID)
      }
    }

    private func commandEnvironment() -> [String: String] {
      var environment = ProcessInfo.processInfo.environment
      let commonPaths = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
      ]
      var pathParts = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
      for path in commonPaths where !pathParts.contains(path) {
        pathParts.append(path)
      }
      environment["PATH"] = pathParts.joined(separator: ":")
      return environment
    }
  #endif
}

private struct TerminalTabStatus {
  var title: String
  var blurb: String
  var detail: String
  var symbolName: String
  var accessibilityLabel: String
  var severity: TerminalTabStatusSeverity

  var tint: Color {
    switch severity {
    case .warning:
      .orange
    case .error:
      .red
    case .cancelled:
      .yellow
    }
  }

  static func exitFailure(
    exitCode: Int32,
    command: String,
    severity: TerminalTabStatusSeverity,
    reference: ExitCodeReferenceEntry?
  ) -> TerminalTabStatus {
    let resolvedSeverity = reference?.severity.terminalSeverity ?? severity
    let title = reference?.title ?? "Exit code \(exitCode)"
    let summary =
      reference?.summary
      ?? "The command exited with a non-zero status. Check the command output for details."
    return TerminalTabStatus(
      title: title,
      blurb: summary,
      detail: "\(command) exited with code \(exitCode).",
      symbolName: resolvedSeverity == .warning
        ? "exclamationmark.triangle.fill" : "xmark.octagon.fill",
      accessibilityLabel: "Command exited with code \(exitCode)",
      severity: resolvedSeverity)
  }

  static func processError(
    command: String,
    message: String,
    severity: TerminalTabStatusSeverity = .error
  ) -> TerminalTabStatus {
    TerminalTabStatus(
      title: severity == .warning ? "Command warning" : "Command failed",
      blurb: "The command could not complete.",
      detail: "\(command)\n\(message)",
      symbolName: severity == .warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill",
      accessibilityLabel: severity == .warning ? "Command warning" : "Command failed",
      severity: severity)
  }

  static func cancelled(command: String, reference: ExitCodeReferenceEntry?) -> TerminalTabStatus {
    let summary =
      reference?.summary
      ?? "The command was cancelled before it finished. Partial output may have been produced."
    return TerminalTabStatus(
      title: reference?.title ?? "Command cancelled",
      blurb: summary,
      detail: "\(command) was cancelled.",
      symbolName: "minus.circle.fill",
      accessibilityLabel: "Command cancelled",
      severity: .cancelled)
  }
}

private enum TerminalTabStatusSeverity {
  case warning
  case error
  case cancelled
}

private extension ExitCodeSeverity {
  var terminalSeverity: TerminalTabStatusSeverity {
    switch self {
    case .warning:
      .warning
    case .error:
      .error
    }
  }
}

private struct TerminalTab: Identifiable {
  let id = UUID()
  var title: String
  var command: String
  var lines: [String]
  var isRunning = false
  var status: TerminalTabStatus?

  var isMain: Bool {
    command == "main"
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

private extension ControlSpec {
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

private extension Optional where Wrapped == String {
  var nonEmpty: String? {
    guard let value = self else { return nil }
    return value.nonEmpty
  }
}

private extension String {
  var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
