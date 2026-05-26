import Foundation
import GUIForCLICore

@MainActor
final class AppKitBundleStateController {
  var fieldValues: [String: String]
  var checkedOptions: [String: Set<String>]
  var configValues: [String: String]
  var configFilePaths: [String: String]
  var bundleState: BundleState
  var manifest: CLIBundleManifest

  let bundleRootURL: URL
  private let bundleStateStore: BundleStateStore
  private let log: (String) -> Void

  init(session: BundleSession, log: @escaping (String) -> Void) {
    fieldValues = session.fieldValues
    checkedOptions = session.checkedOptions
    configValues = session.configValues
    configFilePaths = session.configFilePaths
    bundleState = session.bundleState
    manifest = session.manifest
    bundleRootURL = session.bundleRootURL
    bundleStateStore = session.bundleStateStore
    self.log = log
  }

  func value(for control: ControlSpec) -> String {
    fieldValues[control.id, default: control.value ?? ""]
  }

  func selectedOptions(for control: ControlSpec) -> Set<String> {
    checkedOptions[control.id, default: Set(control.options.filter(\.selected).map(\.id))]
  }

  func setValue(_ value: String, for control: ControlSpec) {
    fieldValues[control.id] = value
    let bindings = BundleSessionLoader.configSettingBindings(in: manifest, forFieldID: control.id)
    guard !bindings.isEmpty else {
      persistFieldValue(value, for: control)
      return
    }

    bundleState.fieldValues.removeValue(forKey: control.id)
    persistBundleState()
    for binding in bindings {
      configValues[binding.control.configValueKey(for: binding.setting)] = value
      saveConfig(binding.control, reportSuccess: false)
    }
  }

  func setSelectedOptions(_ selectedIDs: Set<String>, for control: ControlSpec) {
    checkedOptions[control.id] = selectedIDs
    let bindings = BundleSessionLoader.configSettingBindings(in: manifest, forFieldID: control.id)
    let value = selectedIDs.sorted().joined(separator: ",")
    guard !bindings.isEmpty else {
      persistCheckedOptions(selectedIDs, for: control)
      return
    }

    bundleState.checkedOptions.removeValue(forKey: control.id)
    persistBundleState()
    for binding in bindings {
      configValues[binding.control.configValueKey(for: binding.setting)] = value
      saveConfig(binding.control, reportSuccess: false)
    }
  }

  func configSettingValue(for setting: ConfigSettingSpec, in control: ControlSpec) -> String {
    if let fieldKey = boundFieldKey(for: setting), let value = fieldValues[fieldKey] {
      return value
    }
    return configValues[control.configValueKey(for: setting), default: setting.value ?? ""]
  }

  func setConfigSettingValue(
    _ value: String,
    for setting: ConfigSettingSpec,
    in control: ControlSpec
  ) {
    configValues[control.configValueKey(for: setting)] = value
    if let fieldKey = boundFieldKey(for: setting) {
      fieldValues[fieldKey] = value
      bundleState.fieldValues.removeValue(forKey: fieldKey)
      persistBundleState()
    }
    saveConfig(control, reportSuccess: false)
  }

  func resolvedConfigURL(for control: ControlSpec) -> URL? {
    guard let path = configFilePaths[control.id] ?? control.configFile?.path else {
      return nil
    }
    return BundleSessionLoader.resolvedConfigURL(path: path, rootURL: bundleRootURL)
  }

  func persistConfigFilePath(_ path: String, for control: ControlSpec) {
    configFilePaths[control.id] = path
    bundleState.configFilePaths[control.id] = path
    persistBundleState()
  }

  func saveConfig(_ control: ControlSpec, reportSuccess: Bool = true) {
    BundleConfigFileActions.saveConfig(
      control,
      configURL: resolvedConfigURL(for: control),
      reportSuccess: reportSuccess,
      settingValueProvider: { configSettingValue(for: $0, in: control) },
      log: log)
  }

  func loadConfig(_ control: ControlSpec) {
    BundleConfigFileActions.loadConfig(
      control,
      configURL: resolvedConfigURL(for: control),
      applyConfigValues: { [weak self] values, control in
        self?.applyConfigValues(values, for: control)
      },
      log: log)
  }

  func persistSelectedPageID(_ pageID: String) {
    guard manifest.pages.contains(where: { $0.id == pageID }) else { return }
    bundleState.selectedPageID = pageID
    persistBundleState()
  }

  func persistSetupRun(_ setupRun: BundleSetupRunState) {
    bundleState.setupRun = setupRun
    persistBundleState()
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

  private func boundFieldKey(for setting: ConfigSettingSpec) -> String? {
    manifest.statefulValueControls.first { control in
      control.id == setting.key || control.id == setting.id
    }?.id
  }

  private func persistFieldValue(_ value: String, for control: ControlSpec) {
    guard control.kind.persistsFieldValue else { return }
    bundleState.fieldValues[control.id] = value
    persistBundleState()
  }

  private func persistCheckedOptions(_ selectedIDs: Set<String>, for control: ControlSpec) {
    guard control.kind == .checkboxGroup else { return }
    bundleState.checkedOptions[control.id] = selectedIDs.sorted()
    persistBundleState()
  }

  private func persistBundleState() {
    do {
      try bundleStateStore.save(bundleState)
    } catch {
      log("[state:error] \(error.localizedDescription)")
    }
  }
}
