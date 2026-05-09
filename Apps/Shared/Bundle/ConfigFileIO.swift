import Foundation
import GUIForCLICore

/// Pure-IO helpers for reading and writing bundle config TOML files.
/// `ContentView` wraps these with terminal logging and state mutation.
enum ConfigFileIO {
  enum SaveOutcome {
    case saved(URL, settingCount: Int)
    case missingConfigFile
    case missingPath
    case failed(Error)
  }

  enum LoadOutcome {
    case loaded(URL, values: [String: String])
    case missingPath
    case failed(Error)
  }

  /// Writes the merged TOML for `control` to disk.
  static func save(
    control: ControlSpec,
    configURL: URL?,
    settingValueProvider: (ConfigSettingSpec) -> String
  ) -> SaveOutcome {
    guard control.configFile != nil else { return .missingConfigFile }
    guard let configURL else { return .missingPath }
    do {
      try FileManager.default.createDirectory(
        at: configURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      let contents = try mergedConfigContents(
        control: control,
        existingAt: configURL,
        settingValueProvider: settingValueProvider)
      try contents.write(to: configURL, atomically: true, encoding: .utf8)
      return .saved(configURL, settingCount: control.settings.count)
    } catch {
      return .failed(error)
    }
  }

  /// Parses the TOML at `configURL`.
  static func load(configURL: URL?) -> LoadOutcome {
    guard let configURL else { return .missingPath }
    do {
      let text = try String(contentsOf: configURL, encoding: .utf8)
      let values = try FlatTomlDocument.parse(text)
      return .loaded(configURL, values: values)
    } catch {
      return .failed(error)
    }
  }

  /// Merges current setting values into the existing TOML at `configURL`.
  static func mergedConfigContents(
    control: ControlSpec,
    existingAt configURL: URL,
    settingValueProvider: (ConfigSettingSpec) -> String
  ) throws -> String {
    var values: [String: String] = [:]
    if FileManager.default.fileExists(atPath: configURL.path) {
      let existingText = try String(contentsOf: configURL, encoding: .utf8)
      values = try FlatTomlDocument.parse(existingText)
    }
    for setting in control.settings {
      values[setting.key] = settingValueProvider(setting)
    }
    return FlatTomlDocument.string(from: values)
  }
}
