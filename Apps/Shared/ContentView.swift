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
  @State private var bundleRootURL: URL?
  @State private var isImportingBundle = false
  @StateObject private var terminal = TerminalLogStore()

  init(
    platformName: String,
    manifest: CLIBundleManifest = DemoBundle.wgsExtract,
    bundleRootURL: URL? = DemoBundle.wgsExtractResourceRootURL
  ) {
    self.platformName = platformName
    _manifest = State(initialValue: manifest)
    _selectedPageID = State(initialValue: manifest.defaultPageID)
    _fieldValues = State(initialValue: manifest.initialFieldValues)
    _checkedOptions = State(initialValue: manifest.initialCheckedOptions)
    _configValues = State(
      initialValue: Self.initialConfigValues(for: manifest, rootURL: bundleRootURL))
    _bundleRootURL = State(initialValue: bundleRootURL)
  }

  var body: some View {
    NavigationSplitView {
      VStack(spacing: 0) {
        BundleHeader(manifest: manifest, rootURL: bundleRootURL)
          .padding(.horizontal)
          .padding(.top, 14)
          .padding(.bottom, 10)

        List(selection: $selectedPageID) {
          ForEach(manifest.sidebarPages) { page in
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
          bundleRootURL: bundleRootURL,
          runAction: { action, context in
            terminal.start(
              title: action.title,
              command: action.command.displayCommand(resolving: context))
          },
          saveConfig: { control in
            saveConfig(control)
          }
        )

        Divider()

        TerminalPane(store: terminal)
      }
      .navigationTitle(selectedPage.title)
      .toolbar {
        ToolbarItemGroup {
          Button {
            isImportingBundle = true
          } label: {
            Label("Import Bundle", systemImage: "square.and.arrow.down")
          }

          Button {
            runSetup()
          } label: {
            Label("Setup", systemImage: "checkmark.shield")
          }

          Button {
            if let settingsPage = manifest.settingsPage {
              selectedPageID = settingsPage.id
            } else {
              terminal.appendToMain("No settings page is defined for \(platformName).")
            }
          } label: {
            Label("Settings", systemImage: "gearshape")
          }
          .disabled(manifest.settingsPage == nil)
        }
      }
    }
    .fileImporter(
      isPresented: $isImportingBundle,
      allowedContentTypes: Self.importableBundleTypes,
      allowsMultipleSelection: false
    ) { result in
      importBundle(from: result)
    }
  }

  private var selectedPage: BundlePage {
    manifest.pages.first { $0.id == selectedPageID } ?? manifest.pages[0]
  }

  private static var importableBundleTypes: [UTType] {
    [
      .folder,
      .item,
      UTType(filenameExtension: "json"),
      UTType(filenameExtension: "zip"),
      UTType(filenameExtension: "tar"),
      UTType(filenameExtension: "tgz"),
      UTType(filenameExtension: "gz"),
    ].compactMap { $0 }
  }

  private func importBundle(from result: Result<[URL], Error>) {
    do {
      guard let url = try result.get().first else {
        terminal.appendToMain("[import] No bundle selected.")
        return
      }

      let didAccess = url.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }

      let loaded = try BundleSourceLoader().load(from: url)
      manifest = loaded.manifest
      bundleRootURL = loaded.rootURL
      selectedPageID = loaded.manifest.defaultPageID
      fieldValues = loaded.manifest.initialFieldValues
      checkedOptions = loaded.manifest.initialCheckedOptions
      configValues = Self.initialConfigValues(for: loaded.manifest, rootURL: loaded.rootURL)
      terminal.replaceMain([
        "[import] Loaded bundle: \(loaded.manifest.displayName)",
        "[import] Manifest: \(loaded.manifestURL.path)",
        "[import] Pages: \(loaded.manifest.pages.map(\.title).joined(separator: ", "))",
      ])
    } catch {
      terminal.appendToMain("[import:error] \(error.localizedDescription)")
    }
  }

  private func runSetup() {
    guard let bundleRootURL else {
      terminal.replaceMain([
        "[setup] Import a bundle folder or archive to run setup scripts.",
        "[setup] The built-in demo manifest is loaded without a writable bundle root.",
      ])
      return
    }

    do {
      let commands = try SetupCommandPlanner().plan(for: manifest, rootURL: bundleRootURL)
      terminal.startSetup(commands)
    } catch {
      terminal.appendToMain("[setup:error] \(error.localizedDescription)")
    }
  }

  private func saveConfig(_ control: ControlSpec) {
    guard let configFile = control.configFile else {
      terminal.appendToMain("[config:error] \(control.label) does not specify a config file.")
      return
    }
    guard let bundleRootURL else {
      terminal.appendToMain(
        "[config:error] Import a writable bundle before saving \(configFile.path).")
      return
    }

    do {
      let configURL = bundleRootURL.appendingPathComponent(configFile.path, isDirectory: false)
      try FileManager.default.createDirectory(
        at: configURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      let contents =
        control.settings
        .map { setting in
          "\(tomlKey(setting.key)) = \(tomlValue(configValues[control.configValueKey(for: setting), default: setting.value ?? ""]))"
        }
        .joined(separator: "\n") + "\n"
      try contents.write(to: configURL, atomically: true, encoding: .utf8)
      terminal.appendToMain(
        "[config] Saved \(control.settings.count) setting(s) to \(configURL.path)")
    } catch {
      terminal.appendToMain("[config:error] \(error.localizedDescription)")
    }
  }

  private func tomlKey(_ key: String) -> String {
    if key.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
      return key
    }
    return tomlValue(key)
  }

  private func tomlValue(_ value: String) -> String {
    "\""
      + value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n") + "\""
  }

  private static func initialConfigValues(for manifest: CLIBundleManifest, rootURL: URL?)
    -> [String: String]
  {
    var values = manifest.initialConfigValues
    guard let rootURL else { return values }

    for control in manifest.configEditorControls {
      guard let configFile = control.configFile else { continue }
      let configURL = rootURL.appendingPathComponent(configFile.path, isDirectory: false)
      guard
        let text = try? String(contentsOf: configURL, encoding: .utf8),
        let fileValues = try? parseFlatToml(text)
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

  private static func parseFlatToml(_ text: String) throws -> [String: String] {
    var values: [String: String] = [:]
    for rawLine in text.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty || line.hasPrefix("#") || !line.contains("=") {
        continue
      }
      let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let key = String(parts[0])
        .trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
      let rawValue = String(parts[1]).trimmingCharacters(in: .whitespaces)
      values[key] = parseTomlValue(rawValue)
    }
    return values
  }

  private static func parseTomlValue(_ value: String) -> String {
    guard value.hasPrefix("\""), value.hasSuffix("\"") else {
      return value
    }
    var result = ""
    var iterator = value.dropFirst().dropLast().makeIterator()
    while let character = iterator.next() {
      guard character == "\\" else {
        result.append(character)
        continue
      }
      guard let escaped = iterator.next() else { break }
      switch escaped {
      case "n": result.append("\n")
      case "r": result.append("\r")
      case "t": result.append("\t")
      case "\"": result.append("\"")
      case "\\": result.append("\\")
      default: result.append(escaped)
      }
    }
    return result
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

      VStack(alignment: .leading, spacing: 4) {
        Text(manifest.displayName)
          .font(.headline.weight(.semibold))
          .frame(maxWidth: .infinity, alignment: .center)
        Text(manifest.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
          .help(manifest.summary)
      }
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
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
  var saveConfig: (ControlSpec) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          IconTitleLabel(
            title: page.title,
            iconName: page.iconName,
            iconEmoji: page.iconEmoji,
            defaultSystemImage: page.role == .settings ? "gearshape" : "doc.text"
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
            bundleRootURL: bundleRootURL,
            runAction: runAction,
            saveConfig: saveConfig
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
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
  var saveConfig: (ControlSpec) -> Void

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
            configValues: $configValues,
            bundleRootURL: bundleRootURL,
            runAction: runAction,
            saveConfig: saveConfig
          )
        }

        if !section.actions.isEmpty {
          Divider()
          ActionRow(actions: section.actions) { action in
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
      configValues: configValues,
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
  @Binding var configValues: [String: String]
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
  var saveConfig: (ControlSpec) -> Void

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
          Button("Choose...") {}
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
      VStack(alignment: .leading, spacing: 10) {
        label
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), alignment: .leading)], spacing: 8) {
          ForEach(control.options) { option in
            Toggle(
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
            #if os(macOS)
              .toggleStyle(.checkbox)
            #endif
          }
        }
      }
      .help(control.tooltip ?? "")
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
        configValues: $configValues,
        saveConfig: saveConfig
      )
    }
  }

  private var label: some View {
    HStack(spacing: 6) {
      Text(control.label)
        .font(.headline)
      if let tooltip = control.tooltip {
        Image(systemName: "info.circle")
          .foregroundStyle(.secondary)
          .help(tooltip)
      }
    }
  }

  private func labeledControl<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    LabeledContent {
      content()
        .frame(maxWidth: .infinity)
    } label: {
      label
    }
    .help(control.tooltip ?? "")
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
          Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .help(tooltip)
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
                    ActionButton(action: action) {
                      runAction(action, commandContext(for: row))
                    }
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
  @Binding var configValues: [String: String]
  var saveConfig: (ControlSpec) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        Text(control.label)
          .font(.headline)
        if let tooltip = control.tooltip {
          Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .help(tooltip)
        }
        Spacer()
        Button {
          saveConfig(control)
        } label: {
          Label("Save", systemImage: "square.and.arrow.down")
        }
        .disabled(control.configFile == nil)
      }

      if let configFile = control.configFile {
        Text(configFile.path)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }

      ForEach(control.settings) { setting in
        ConfigSettingRenderer(setting: setting, value: binding(for: setting))
      }
    }
    .help(control.tooltip ?? "")
  }

  private func binding(for setting: ConfigSettingSpec) -> Binding<String> {
    Binding(
      get: { configValues[control.configValueKey(for: setting), default: setting.value ?? ""] },
      set: { configValues[control.configValueKey(for: setting)] = $0 }
    )
  }
}

private struct ConfigSettingRenderer: View {
  let setting: ConfigSettingSpec
  @Binding var value: String

  var body: some View {
    LabeledContent {
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
            Button("Choose...") {}
          }
        }
      }
    } label: {
      HStack(spacing: 6) {
        Text(setting.label)
        if let tooltip = setting.tooltip {
          Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .help(tooltip)
        }
      }
    }
    .help(setting.tooltip ?? "")
  }
}

private struct ActionRow: View {
  let actions: [ActionSpec]
  var runAction: (ActionSpec) -> Void

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)], spacing: 10) {
      ForEach(actions) { action in
        ActionButton(action: action) {
          runAction(action)
        }
      }
    }
  }
}

private struct ActionButton: View {
  let action: ActionSpec
  var run: () -> Void

  var body: some View {
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
    .help(action.tooltip ?? action.command.displayCommand)
    .accessibilityLabel(action.title)
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

private extension CommandSpec {
  func displayCommand(resolving context: CommandRenderContext) -> String {
    ([executable] + arguments)
      .map { interpolate($0, context: context) }
      .joined(separator: " ")
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

  func start(title: String, command: String) {
    let tab = TerminalTab(
      title: title, command: command,
      lines: [
        "$ \(command)",
        "[queued] Preparing command environment...",
      ])
    tabs.append(tab)
    selectedTabID = tab.id

    tasks[tab.id] = Task { @MainActor [weak self] in
      await self?.simulateRun(tabID: tab.id, command: command)
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
    tabs.removeAll { $0.id == selectedTabID }
    self.selectedTabID = tabs.first?.id
  }

  private func simulateRun(tabID: UUID, command: String) async {
    do {
      try await Task.sleep(for: .milliseconds(250))
      append("[running] \(command)", to: tabID)
      try await Task.sleep(for: .milliseconds(350))
      append("[stdout] This starter currently simulates CLI execution.", to: tabID)
      append(
        "[stdout] Wire CommandSpec to Process on macOS when bundle execution is enabled.", to: tabID
      )
      try await Task.sleep(for: .milliseconds(250))
      append("[done] exit code 0", to: tabID)
    } catch {
      append("[cancelled] \(command)", to: tabID)
    }
    tasks[tabID] = nil
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
}

private struct TerminalTab: Identifiable {
  let id = UUID()
  var title: String
  var command: String
  var lines: [String]
}

private extension CLIBundleManifest {
  var sidebarPages: [BundlePage] {
    pages.filter { $0.role == .page }
  }

  var settingsPage: BundlePage? {
    pages.first { $0.role == .settings }
  }

  var defaultPageID: String? {
    sidebarPages.first?.id ?? pages.first?.id
  }

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

  var configEditorControls: [ControlSpec] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
      .filter { $0.kind == .configEditor }
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
