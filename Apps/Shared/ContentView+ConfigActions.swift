import GUIForCLICore
import SwiftUI

extension ContentView {
  // MARK: - Save / load

  func saveConfig(_ control: ControlSpec, reportSuccess: Bool = true) {
    switch ConfigFileIO.save(
      control: control,
      configURL: resolvedConfigURL(for: control),
      settingValueProvider: { configSettingValue(for: $0, in: control) })
    {
    case .saved(let url, let count):
      if reportSuccess {
        terminal.appendToMain("[config] Saved \(count) setting(s) to \(url.path)")
      }
    case .missingConfigFile:
      terminal.appendToMain("[config:error] \(control.label) does not specify a config file.")
    case .missingPath:
      terminal.appendToMain("[config:error] Choose a settings file path before saving.")
    case .failed(let error):
      terminal.appendToMain("[config:error] \(error.localizedDescription)")
    }
  }

  func loadConfig(_ control: ControlSpec) {
    switch ConfigFileIO.load(configURL: resolvedConfigURL(for: control)) {
    case .loaded(let url, let values):
      applyConfigValues(values, for: control)
      terminal.appendToMain("[config] Loaded settings from \(url.path)")
    case .missingPath:
      terminal.appendToMain("[config:error] Choose a settings file path before loading.")
    case .failed(let error):
      terminal.appendToMain("[config:error] \(error.localizedDescription)")
    }
  }

  func persistConfigFilePath(_ path: String, for control: ControlSpec) {
    configFilePaths[control.id] = path
    bundleState.configFilePaths[control.id] = path
    persistBundleState()
  }

  // MARK: - Field / option / setting handlers

  func fieldValueChanged(_ value: String, for control: ControlSpec) {
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

  func checkedOptionsChanged(_ selectedIDs: Set<String>, for control: ControlSpec) {
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

  func configSettingChanged(
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

  // MARK: - Helpers

  func resolvedConfigURL(for control: ControlSpec) -> URL? {
    guard let path = configFilePaths[control.id] ?? control.configFile?.path else {
      return nil
    }
    return BundleSessionLoader.resolvedConfigURL(path: path, rootURL: bundleRootURL)
  }

  func configSettingValue(for setting: ConfigSettingSpec, in control: ControlSpec) -> String {
    if let fieldKey = boundFieldKey(for: setting), let value = fieldValues[fieldKey] {
      return value
    }
    return configValues[control.configValueKey(for: setting), default: setting.value ?? ""]
  }

  func boundFieldKey(for setting: ConfigSettingSpec) -> String? {
    if fieldValues.keys.contains(setting.key) { return setting.key }
    if fieldValues.keys.contains(setting.id) { return setting.id }
    return nil
  }

  func applyConfigValues(_ fileValues: [String: String], for control: ControlSpec) {
    for setting in control.settings {
      guard let value = fileValues[setting.key] else { continue }
      configValues[control.configValueKey(for: setting)] = value
      if let fieldKey = boundFieldKey(for: setting) {
        fieldValues[fieldKey] = value
      }
    }
  }

  // MARK: - State persistence

  func persistFieldValue(_ value: String, for control: ControlSpec) {
    guard control.kind.persistsFieldValue else { return }
    bundleState.fieldValues[control.id] = value
    persistBundleState()
  }

  func persistCheckedOptions(_ selectedIDs: Set<String>, for control: ControlSpec) {
    guard control.kind == .checkboxGroup else { return }
    bundleState.checkedOptions[control.id] = selectedIDs.sorted()
    persistBundleState()
  }

  func persistBundleState() {
    guard let bundleStateStore else { return }
    do {
      try bundleStateStore.save(bundleState)
    } catch {
      terminal.appendToMain("[state:error] \(error.localizedDescription)")
    }
  }

  func flushStartupMessages() {
    let messages = startupMessages
    guard !messages.isEmpty else { return }
    startupMessages.removeAll()
    for message in messages {
      terminal.appendToMain(message)
    }
  }
}
