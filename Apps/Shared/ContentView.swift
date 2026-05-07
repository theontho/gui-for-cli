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

  @State private var manifest: CLIBundleManifest
  @State private var selectedPageID: String?
  @State private var fieldValues: [String: String]
  @State private var checkedOptions: [String: Set<String>]
  @State private var configValues: [String: String]
  @State private var configFilePaths: [String: String]
  @State private var bundleRootURL: URL?
  @State private var startupMessages: [String]
  @StateObject private var terminal = TerminalLogStore()

  init(
    platformName: String,
    manifest: CLIBundleManifest = DemoBundle.wgsExtract,
    bundleRootURL: URL? = DemoBundle.wgsExtractResourceRootURL
  ) {
    self.platformName = platformName
    let configFilePaths = Self.initialConfigFilePaths(for: manifest)
    let startupMessages = Self.bootstrapConfigFiles(
      for: manifest,
      rootURL: bundleRootURL,
      configFilePaths: configFilePaths)
    let configValues = Self.initialConfigValues(
      for: manifest,
      rootURL: bundleRootURL,
      configFilePaths: configFilePaths)
    _manifest = State(initialValue: manifest)
    _selectedPageID = State(initialValue: manifest.pages.first?.id)
    _fieldValues = State(
      initialValue: Self.initialFieldValues(for: manifest, configValues: configValues))
    _checkedOptions = State(initialValue: manifest.initialCheckedOptions)
    _configValues = State(initialValue: configValues)
    _configFilePaths = State(initialValue: configFilePaths)
    _bundleRootURL = State(initialValue: bundleRootURL)
    _startupMessages = State(initialValue: startupMessages)
  }

  var body: some View {
    NavigationSplitView {
      VStack(spacing: 0) {
        BundleHeader(manifest: manifest, rootURL: bundleRootURL)
          .padding(.horizontal)
          .padding(.top, 14)
          .padding(.bottom, 10)

        List(selection: $selectedPageID) {
          ForEach(manifest.pages) { page in
            IconTitleLabel(
              title: page.title,
              iconName: page.iconName,
              iconEmoji: page.iconEmoji,
              defaultSystemImage: "doc.text"
            )
            .tag(page.id)
          }
        }
      }
      .navigationTitle("Pages")
    } detail: {
      VStack(spacing: 0) {
        PageRenderer(
          page: selectedPage,
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
          }
        )

        Divider()

        TerminalPane(store: terminal)
      }
      .onAppear(perform: flushStartupMessages)
      .navigationTitle(selectedPage.title)
    }
  }

  private var selectedPage: BundlePage {
    manifest.pages.first { $0.id == selectedPageID } ?? manifest.pages[0]
  }

  private func saveConfig(_ control: ControlSpec) {
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
      let contents = FlatTomlDocument.string(
        from: control.settings.map { setting in
          (setting.key, configSettingValue(for: setting, in: control))
        })
      try contents.write(to: configURL, atomically: true, encoding: .utf8)
      terminal.appendToMain(
        "[config] Saved \(control.settings.count) setting(s) to \(configURL.path)")
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
      paths[control.id] =
        UserDefaults.standard.string(
          forKey: configFilePathDefaultsKey(manifest: manifest, control: control))
        ?? configFile.path
    }
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
    for control in manifest.configEditorControls {
      for setting in control.settings {
        let configValue = configValues[
          control.configValueKey(for: setting), default: setting.value ?? ""]
        guard !configValue.isEmpty else { continue }
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

  private static func initialConfigValues(
    for manifest: CLIBundleManifest,
    rootURL: URL?,
    configFilePaths: [String: String]
  )
    -> [String: String]
  {
    var values = manifest.initialConfigValues

    for control in manifest.configEditorControls {
      guard
        control.configFile != nil,
        let path = configFilePaths[control.id],
        let configURL = resolvedConfigURL(path: path, rootURL: rootURL)
      else { continue }
      guard
        let text = try? String(contentsOf: configURL, encoding: .utf8),
        let fileValues = try? FlatTomlDocument.parse(text)
      else {
        continue
      }
      for setting in control.settings {
        if let value = fileValues[setting.key] {
          values[control.configValueKey(for: setting)] = value
        }
      }
    }
    return values
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
        Text(manifest.displayName)
          .font(.headline.weight(.semibold))
          .lineLimit(2)
          .multilineTextAlignment(.center)
        InfoButton(text: manifest.summary)
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
        Label(title, systemImage: iconName.nonEmpty ?? defaultSystemImage)
          .labelStyle(.iconOnly)
      } else {
        Label(title, systemImage: iconName.nonEmpty ?? defaultSystemImage)
          .labelStyle(.titleAndIcon)
      }
    }
  }
}

private struct PageRenderer: View {
  let page: BundlePage
  @Binding var fieldValues: [String: String]
  @Binding var checkedOptions: [String: Set<String>]
  @Binding var configValues: [String: String]
  @Binding var configFilePaths: [String: String]
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
  var saveConfig: (ControlSpec) -> Void
  var loadConfig: (ControlSpec) -> Void
  var persistConfigFilePath: (String, ControlSpec) -> Void

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

        ForEach(page.sections) { section in
          SectionRenderer(
            section: section,
            fieldValues: $fieldValues,
            checkedOptions: $checkedOptions,
            configValues: $configValues,
            configFilePaths: $configFilePaths,
            bundleRootURL: bundleRootURL,
            runAction: runAction,
            saveConfig: saveConfig,
            loadConfig: loadConfig,
            persistConfigFilePath: persistConfigFilePath
          )
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(.background)
  }
}

private struct SectionRenderer: View {
  let section: PageSection
  @Binding var fieldValues: [String: String]
  @Binding var checkedOptions: [String: Set<String>]
  @Binding var configValues: [String: String]
  @Binding var configFilePaths: [String: String]
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
  var saveConfig: (ControlSpec) -> Void
  var loadConfig: (ControlSpec) -> Void
  var persistConfigFilePath: (String, ControlSpec) -> Void

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
            persistConfigFilePath: persistConfigFilePath
          )
        }

        if !section.actions.isEmpty {
          Divider()
          ActionRow(actions: section.actions, context: commandContext()) { action in
            runAction(action, commandContext())
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
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

  private func binding(for control: ControlSpec) -> Binding<String> {
    Binding(
      get: { fieldValues[control.id, default: control.value ?? ""] },
      set: { fieldValues[control.id] = $0 }
    )
  }

  private func checkedBinding(for control: ControlSpec) -> Binding<Set<String>> {
    Binding(
      get: {
        checkedOptions[control.id, default: Set(control.options.filter(\.selected).map(\.id))]
      },
      set: { checkedOptions[control.id] = $0 }
    )
  }

  private func commandContext(rowValues: [String: String] = [:]) -> CommandRenderContext {
    CommandRenderContext(
      fieldValues: fieldValues,
      checkedOptions: checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configValues.merging(fieldValues) { _, fieldValue in fieldValue },
      rowValues: rowValues,
      bundleRootPath: bundleRootURL?.path
    )
  }
}

private struct ControlRenderer: View {
  let control: ControlSpec
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

  var body: some View {
    switch control.kind {
    case .text:
      labeledControl {
        TextField(control.placeholder ?? "", text: $value)
      }
    case .path:
      labeledControl {
        HStack {
          TextField(control.placeholder ?? "", text: $value)
          PathPickerButton(path: $value)
        }
      }
    case .dropdown:
      labeledControl {
        Picker("", selection: $value) {
          ForEach(control.options) { option in
            Text(option.title).tag(option.id)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
      }
    case .toggle:
      labeledControl {
        Toggle("", isOn: Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" }))
          .labelsHidden()
      }
    case .checkboxGroup:
      if control.options.count == 1, let option = control.options.first {
        labeledControl {
          checkbox(for: option)
        }
      } else {
        VStack(alignment: .leading, spacing: 10) {
          label
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), alignment: .leading)], spacing: 8) {
            ForEach(control.options) { option in
              checkbox(for: option)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(control.tooltip ?? "")
      }
    case .infoGrid:
      VStack(alignment: .leading, spacing: 10) {
        label
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), alignment: .leading)], spacing: 8) {
          ForEach(control.options) { option in
            Text(option.title)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      }
      .help(control.tooltip ?? "")
    case .libraryList:
      LibraryListControl(
        control: control,
        fieldValues: fieldValues,
        checkedOptions: checkedOptions,
        configValues: configValues,
        bundleRootURL: bundleRootURL,
        runAction: runAction
      )
    case .configEditor:
      ConfigEditorControl(
        control: control,
        fieldValues: $allFieldValues,
        configValues: $configValues,
        configFilePaths: $configFilePaths,
        saveConfig: saveConfig,
        loadConfig: loadConfig,
        persistConfigFilePath: persistConfigFilePath
      )
    }
  }

  private var label: some View {
    HStack(spacing: 6) {
      Text(control.label)
        .font(.headline)
      if let tooltip = control.tooltip {
        InfoButton(text: tooltip)
      }
    }
  }

  private func labeledControl<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    LeadingFormRow {
      label
    } content: {
      content()
    }
    .help(control.tooltip ?? "")
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
  let fieldValues: [String: String]
  let checkedOptions: [String: Set<String>]
  let configValues: [String: String]
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Text(control.label)
          .font(.headline)
        if let tooltip = control.tooltip {
          InfoButton(text: tooltip)
        }
      }

      let rows = control.hydratedRows
      if rows.isEmpty {
        Text("No library items are defined.")
          .foregroundStyle(.secondary)
      } else {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
          GridRow {
            ForEach(control.columns) { column in
              Text(column.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            if !control.rowActions.isEmpty {
              Text("Actions")
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
                  if column.id == "name", let status = row.status {
                    Text(status)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
                .help(row.tooltip ?? "")
              }

              if !control.rowActions.isEmpty {
                HStack(spacing: 8) {
                  ForEach(control.rowActions) { action in
                    let context = commandContext(for: row)
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
    }
    .help(control.tooltip ?? "")
  }

  private func displayValue(for column: ListColumnSpec, row: ListRowSpec) -> String {
    if column.id == "name" {
      return row.title ?? row.values[column.id] ?? row.id
    }
    if column.id == "status" {
      return row.status ?? row.values[column.id] ?? ""
    }
    return row.values[column.id] ?? ""
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
}

private struct ConfigEditorControl: View {
  let control: ControlSpec
  @Binding var fieldValues: [String: String]
  @Binding var configValues: [String: String]
  @Binding var configFilePaths: [String: String]
  var saveConfig: (ControlSpec) -> Void
  var loadConfig: (ControlSpec) -> Void
  var persistConfigFilePath: (String, ControlSpec) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        Text(control.label)
          .font(.headline)
        if let tooltip = control.tooltip {
          InfoButton(text: tooltip)
        }
        Spacer()
        Button {
          saveConfig(control)
        } label: {
          Label("Save", systemImage: "square.and.arrow.down")
        }
        .disabled(control.configFile == nil)
      }

      if control.configFile != nil {
        LeadingFormRow {
          Text("Settings File")
            .font(.headline)
        } content: {
          HStack {
            TextField("config/settings.toml", text: configFilePathBinding)
              .font(.body.monospaced())
            PathPickerButton(path: configFilePathBinding, canChooseDirectories: false)
            Button {
              loadConfig(control)
            } label: {
              Label("Load", systemImage: "arrow.clockwise")
            }
          }
        }
      }

      ForEach(control.settings) { setting in
        ConfigSettingRenderer(setting: setting, value: binding(for: setting))
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
        configValues[control.configValueKey(for: setting)] = newValue
        if let fieldKey = boundFieldKey(for: setting) {
          fieldValues[fieldKey] = newValue
        }
      }
    )
  }

  private var configFilePathBinding: Binding<String> {
    Binding(
      get: { configFilePaths[control.id, default: control.configFile?.path ?? ""] },
      set: { newPath in
        configFilePaths[control.id] = newPath
        persistConfigFilePath(newPath, control)
      }
    )
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
}

private struct ConfigSettingRenderer: View {
  let setting: ConfigSettingSpec
  @Binding var value: String

  var body: some View {
    LeadingFormRow {
      HStack(spacing: 6) {
        Text(setting.label)
        if let tooltip = setting.tooltip {
          InfoButton(text: tooltip)
        }
      }
    } content: {
      switch setting.kind {
      case .dropdown:
        Picker("", selection: $value) {
          ForEach(setting.options) { option in
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
            PathPickerButton(path: $value)
          }
        }
      }
    }
    .help(setting.tooltip ?? "")
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
  var canChooseFiles = true
  var canChooseDirectories = true
  @State private var isImportingPath = false
  @State private var pickerErrorMessage = ""
  @State private var isShowingPickerError = false

  var body: some View {
    Button("Choose...") {
      choosePath()
    }
    .fileImporter(
      isPresented: $isImportingPath,
      allowedContentTypes: importableContentTypes,
      allowsMultipleSelection: false
    ) { result in
      handleImportedPath(result)
    }
    .alert("Could not choose path", isPresented: $isShowingPickerError) {
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
      if !path.isEmpty {
        panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
      }

      guard panel.runModal() == .OK, let url = panel.url else {
        return
      }
      path = url.path
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
    } catch {
      pickerErrorMessage = error.localizedDescription
      isShowingPickerError = true
    }
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
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)], spacing: 10) {
      ForEach(actions) { action in
        ActionButton(action: action) {
          runAction(action)
        }
        .environment(\.commandRenderContext, context)
      }
    }
  }
}

private struct ActionButton: View {
  @Environment(\.commandRenderContext) private var context
  let action: ActionSpec
  var run: () -> Void

  var body: some View {
    let missingPlaceholders = action.command.missingPlaceholders(resolving: context)
    Button(role: action.role == .destructive ? .destructive : nil, action: run) {
      IconTitleLabel(
        title: action.title,
        iconName: action.iconName,
        iconEmoji: action.iconEmoji,
        defaultSystemImage: "play",
        iconOnly: action.iconOnly
      )
      .frame(maxWidth: action.iconOnly ? nil : .infinity)
    }
    .controlSize(.regular)
    .disabled(!missingPlaceholders.isEmpty)
    .help(helpText(missingPlaceholders: missingPlaceholders))
    .accessibilityLabel(action.title)
  }

  private func helpText(missingPlaceholders: [String]) -> String {
    if !missingPlaceholders.isEmpty {
      return "Fill in \(missingPlaceholders.joined(separator: ", ")) before running this action."
    }
    return action.tooltip ?? action.command.displayCommand(resolving: context)
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
      Text(text)
        .font(.callout)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }
  }
}

private struct CommandRenderContext {
  var fieldValues: [String: String] = [:]
  var checkedOptions: [String: String] = [:]
  var configValues: [String: String] = [:]
  var rowValues: [String: String] = [:]
  var bundleRootPath: String?

  func value(for placeholder: String) -> String? {
    if placeholder == "bundleRoot" {
      return bundleRootPath
    }
    if placeholder.hasPrefix("row.") {
      return rowValues[String(placeholder.dropFirst(4))]
    }
    if placeholder.hasPrefix("config.") {
      return configValues[String(placeholder.dropFirst(7))]
    }
    return rowValues[placeholder]
      ?? fieldValues[placeholder]
      ?? checkedOptions[placeholder]
      ?? configValues[placeholder]
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
    RenderedCommand(
      executable: interpolate(executable, context: context),
      arguments: arguments.map { interpolate($0, context: context) }
    )
  }

  func displayCommand(resolving context: CommandRenderContext) -> String {
    renderedCommand(resolving: context).displayCommand
  }

  func missingPlaceholders(resolving context: CommandRenderContext) -> [String] {
    var missing: [String] = []
    for placeholder in placeholders(in: [executable] + arguments) {
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

private struct TerminalPane: View {
  @ObservedObject var store: TerminalLogStore

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Label("Command Output", systemImage: "terminal")
          .font(.headline)

        Picker("Tab", selection: $store.selectedTabID) {
          ForEach(store.tabs) { tab in
            Text(tab.title).tag(Optional(tab.id))
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 220)

        Spacer()

        Button {
          store.closeSelectedTab()
        } label: {
          Label("Close or Clear", systemImage: "xmark.circle")
        }
        .disabled(store.tabs.isEmpty)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

      Divider()

      ScrollView {
        Text(store.selectedTab?.lines.joined(separator: "\n") ?? "")
          .font(.system(.callout, design: .monospaced))
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
          .padding(12)
      }
      .background(.regularMaterial)
    }
    .frame(height: 240)
  }
}

@MainActor
private final class TerminalLogStore: ObservableObject {
  @Published var tabs: [TerminalTab] = [
    TerminalTab(
      title: "Main", command: "main",
      lines: [
        "[08:00:00] GUI for CLI started.",
        "[08:00:00] Loaded sample bundle: WGS Extract.",
        "[08:00:00] Bundle setup can check PATH tools, bundled scripts, and Homebrew packages.",
      ])
  ]
  @Published var selectedTabID: UUID?

  private var tasks: [UUID: Task<Void, Never>] = [:]
  #if os(macOS)
    private var processes: [UUID: Process] = [:]
  #endif

  init() {
    selectedTabID = tabs.first?.id
  }

  var selectedTab: TerminalTab? {
    tabs.first { $0.id == selectedTabID }
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
      ])
    tabs.append(tab)
    selectedTabID = tab.id

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
      }
    )
    tabs.append(tab)
    selectedTabID = tab.id

    tasks[tab.id] = Task { @MainActor [weak self] in
      await self?.runSetup(tabID: tab.id, commands: commands)
    }
  }

  func closeSelectedTab() {
    guard let selectedTabID else { return }
    if tabs.first?.id == selectedTabID {
      tabs[0].lines.removeAll()
      tabs[0].lines.append("[cleared] Main log cleared.")
      return
    }

    tasks[selectedTabID]?.cancel()
    tasks[selectedTabID] = nil
    #if os(macOS)
      processes[selectedTabID]?.terminate()
      processes[selectedTabID] = nil
    #endif
    tabs.removeAll { $0.id == selectedTabID }
    self.selectedTabID = tabs.first?.id
  }

  private func runCommand(tabID: UUID, command: RenderedCommand, workingDirectory: URL?) async {
    #if os(macOS)
      do {
        append("[running] \(command.displayCommand)", to: tabID)
        let exitStatus = try await runProcess(
          tabID: tabID,
          command: command,
          workingDirectory: workingDirectory)
        if Task.isCancelled {
          append("[cancelled] \(command.displayCommand)", to: tabID)
        } else if exitStatus == 0 {
          append("[done] exit code 0", to: tabID)
        } else {
          append("[exit \(exitStatus)] \(command.displayCommand)", to: tabID)
        }
      } catch is CancellationError {
        append("[cancelled] \(command.displayCommand)", to: tabID)
      } catch {
        append("[error] \(error.localizedDescription)", to: tabID)
      }
      processes[tabID] = nil
      tasks[tabID] = nil
    #else
      append("[error] Command execution is only available on macOS.", to: tabID)
      tasks[tabID] = nil
    #endif
  }

  private func runSetup(tabID: UUID, commands: [SetupCommand]) async {
    let runner = SetupCommandRunner()
    for command in commands {
      if Task.isCancelled {
        append("[cancelled] setup stopped", to: tabID)
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
          if !command.optional { break }
        } else {
          append("[ok] \(command.label)", to: tabID)
        }
      } catch {
        append("[error] \(command.label): \(error.localizedDescription)", to: tabID)
        if !command.optional { break }
      }
    }
    tasks[tabID] = nil
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

private struct TerminalTab: Identifiable {
  let id = UUID()
  var title: String
  var command: String
  var lines: [String]
}

private extension CLIBundleManifest {
  var initialFieldValues: [String: String] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
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
      let tooltip = template.tooltip.map { interpolate($0, values: item.values) }.nonEmpty

      return ListRowSpec(
        id: id,
        title: title,
        values: values,
        status: status,
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
