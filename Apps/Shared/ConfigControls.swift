import GUIForCLICore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

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
