import GUIForCLICore
import SwiftUI
import UniformTypeIdentifiers

struct ConfigEditorControl: View {
  @EnvironmentObject private var configStore: BundleConfigStore
  let control: ControlSpec
  let localizationLabels: BundleLocalizationLabels
  let bundleRootURL: URL?
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
                configStore.loadConfig(control)
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
      get: { configStore.configSettingValue(for: setting, in: control) },
      set: { newValue in
        configStore.configSettingChanged(newValue, for: setting, in: control)
      }
    )
  }

  private var configFilePathBinding: Binding<String> {
    Binding(
      get: {
        configStore.configFilePaths[control.id, default: control.configFile?.path ?? ""]
      },
      set: { newPath in
        configStore.configFilePaths[control.id] = newPath
        configStore.persistConfigFilePath(newPath, for: control)
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
    configStore.loadConfig(control)
  }

  private var dataSourceContext: CommandRenderContext {
    var settingValues = configStore.configValues
    for setting in control.settings {
      let value = configStore.configValues[
        control.configValueKey(for: setting), default: setting.value ?? ""]
      settingValues[setting.id] = value
      settingValues[setting.key] = value
    }
    return CommandRenderContext(
      fieldValues: configStore.fieldValues.merging(settingValues) { _, settingValue in
        settingValue
      },
      configValues: settingValues,
      bundleRootPath: bundleRootURL?.path)
  }
}
