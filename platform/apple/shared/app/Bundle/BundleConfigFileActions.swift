import Foundation
import GUIForCLICore

@MainActor
enum BundleConfigFileActions {
  static func saveConfig(
    _ control: ControlSpec,
    configURL: URL?,
    reportSuccess: Bool = true,
    settingValueProvider: (ConfigSettingSpec) -> String,
    log: (String) -> Void
  ) {
    switch ConfigFileIO.save(
      control: control,
      configURL: configURL,
      settingValueProvider: settingValueProvider)
    {
    case .saved(let url, let count):
      if reportSuccess {
        log("[config] Saved \(count) setting(s) to \(url.path)")
      }
    case .missingConfigFile:
      log("[config:error] \(control.label) does not specify a config file.")
    case .missingPath:
      log("[config:error] Choose a settings file path before saving.")
    case .failed(let error):
      log("[config:error] \(error.localizedDescription)")
    }
  }

  static func loadConfig(
    _ control: ControlSpec,
    configURL: URL?,
    applyConfigValues: ([String: String], ControlSpec) -> Void,
    log: (String) -> Void
  ) {
    switch ConfigFileIO.load(configURL: configURL) {
    case .loaded(let url, let values):
      applyConfigValues(values, control)
      log("[config] Loaded settings from \(url.path)")
    case .missingPath:
      log("[config:error] Choose a settings file path before loading.")
    case .failed(let error):
      log("[config:error] \(error.localizedDescription)")
    }
  }
}
