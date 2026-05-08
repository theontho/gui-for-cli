import GUIForCLICore
import SwiftUI
import UniformTypeIdentifiers

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
