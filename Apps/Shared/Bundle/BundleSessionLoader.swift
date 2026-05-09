import Foundation
import GUIForCLICore

/// Bootstrapped per-bundle session state, ready to seed `ContentView`.
struct BundleSession {
  var manifest: CLIBundleManifest
  var localizationOptions: [BundleLocalizationOption]
  var localizationLabels: BundleLocalizationLabels
  var localizationCode: String
  var usingSystemDefaultLocale: Bool
  var bundleRootURL: URL
  var bundleState: BundleState
  var bundleStateStore: BundleStateStore
  var configFilePaths: [String: String]
  var configValues: [String: String]
  var fieldValues: [String: String]
  var checkedOptions: [String: Set<String>]
  var startupMessages: [String]
}

/// Loads, prepares the workspace, applies state, and produces a `BundleSession`
/// in one place so `ContentView.init` doesn't have to orchestrate it.
enum BundleSessionLoader {
  static func bootstrap(
    sourceRootURL: URL,
    fallbackManifest: CLIBundleManifest,
    systemPreferences: [String]
  ) -> BundleSession {
    let probe = try? BundleSourceLoader().load(from: sourceRootURL)
    let workspace = prepareBundleWorkspace(
      for: probe?.manifest ?? fallbackManifest,
      sourceRootURL: sourceRootURL)
    let stateStore = BundleStateStore(workspaceURL: workspace.rootURL)
    var bundleState = stateStore.load()

    let storedLocalizationCode = bundleState.localizationCode
    let availableOptions = probe?.localizationOptions ?? []
    let resolvedRequest =
      storedLocalizationCode
      ?? BundleSourceLoader.matchLocalizationCode(
        preferences: systemPreferences,
        options: availableOptions)
    let loaded = try? BundleSourceLoader().load(
      from: sourceRootURL,
      localizationCode: resolvedRequest)
    let activeManifest = loaded?.manifest ?? fallbackManifest

    let configFilePaths = initialConfigFilePaths(for: activeManifest, state: &bundleState)
    let bootstrapMessages = bootstrapConfigFiles(
      for: activeManifest,
      rootURL: workspace.rootURL,
      configFilePaths: configFilePaths)
    let initialConfig = initialConfigValues(
      for: activeManifest,
      rootURL: workspace.rootURL,
      configFilePaths: configFilePaths)

    return BundleSession(
      manifest: activeManifest,
      localizationOptions: loaded?.localizationOptions ?? [],
      localizationLabels: loaded?.localizationLabels ?? BundleLocalizationLabels(),
      localizationCode: loaded?.localizationCode ?? BundleSourceLoader.defaultLocalizationCode,
      usingSystemDefaultLocale: storedLocalizationCode == nil,
      bundleRootURL: workspace.rootURL,
      bundleState: bundleState,
      bundleStateStore: stateStore,
      configFilePaths: configFilePaths,
      configValues: initialConfig.values,
      fieldValues: initialFieldValues(
        for: activeManifest, configValues: initialConfig.values, state: bundleState),
      checkedOptions: initialCheckedOptions(
        for: activeManifest, configValues: initialConfig.values, state: bundleState),
      startupMessages: workspace.messages + bootstrapMessages + initialConfig.messages)
  }

  // MARK: - Workspace

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

  // MARK: - Initial state factories

  static func initialConfigFilePaths(
    for manifest: CLIBundleManifest,
    state: inout BundleState
  ) -> [String: String] {
    var paths: [String: String] = [:]
    for control in manifest.configEditorControls {
      guard let configFile = control.configFile else { continue }
      if let persistedPath = state.configFilePaths[control.id],
        !shouldDiscardLegacyConfigPath(persistedPath, defaultPath: configFile.path)
      {
        paths[control.id] = persistedPath
      } else {
        state.configFilePaths.removeValue(forKey: control.id)
        paths[control.id] = configFile.path
      }
    }
    return paths
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

  static func initialFieldValues(
    for manifest: CLIBundleManifest,
    configValues: [String: String],
    state: BundleState
  ) -> [String: String] {
    var values = manifest.initialFieldValues
    for control in manifest.statefulValueControls
    where configSettingBindings(in: manifest, forFieldID: control.id).isEmpty {
      if let persistedValue = state.fieldValues[control.id] {
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

  static func initialCheckedOptions(
    for manifest: CLIBundleManifest,
    configValues: [String: String],
    state: BundleState
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
      } else if let persistedIDs = state.checkedOptions[control.id] {
        values[control.id] = Set(persistedIDs)
      }
    }
    return values
  }

  static func initialConfigValues(
    for manifest: CLIBundleManifest,
    rootURL: URL?,
    configFilePaths: [String: String]
  ) -> InitialConfigValues {
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

  static func resolvedConfigURL(path: String, rootURL: URL?) -> URL? {
    guard let rootURL else { return nil }
    return BundlePathResolver.resolveConfigFilePath(path, rootURL: rootURL)
  }

  // MARK: - Manifest queries

  static func configSettingBindings(
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

  // MARK: - System locale

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
}
