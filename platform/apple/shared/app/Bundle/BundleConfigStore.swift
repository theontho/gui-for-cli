import Foundation
import GUIForCLICore
import SwiftUI

/// Owns the mutable per-bundle configuration state (form values, checkbox
/// selections, bound TOML config values, on-disk paths) plus the
/// persistence layer that mirrors them into the bundle's workspace
/// `state.json`. Lifted out of `ContentView` so the SwiftUI tree can
/// share a single source of truth via `@EnvironmentObject` instead of
/// threading half a dozen `@Binding`s and closures through every
/// renderer.
@MainActor
final class BundleConfigStore: ObservableObject {
  @Published var fieldValues: [String: String]
  @Published var checkedOptions: [String: Set<String>]
  @Published var configValues: [String: String]
  @Published var configFilePaths: [String: String]
  @Published var bundleState: BundleState

  /// Latest manifest in effect. Kept as a plain (non-published) property
  /// because re-renders are already driven by ContentView's own
  /// `@State manifest`; the store reads it on-demand inside its action
  /// methods to look up config-setting bindings against the current
  /// page graph (which can change after a hot-reload or locale switch).
  var manifest: CLIBundleManifest

  let bundleStateStore: BundleStateStore?
  let bundleRootURL: URL?
  /// Sink for user-facing diagnostic lines (errors, save/load receipts).
  /// Injected to avoid coupling the store to `TerminalLogStore` directly.
  private let log: (String) -> Void

  init(session: BundleSession, log: @escaping (String) -> Void) {
    self.fieldValues = session.fieldValues
    self.checkedOptions = session.checkedOptions
    self.configValues = session.configValues
    self.configFilePaths = session.configFilePaths
    self.bundleState = session.bundleState
    self.manifest = session.manifest
    self.bundleStateStore = session.bundleStateStore
    self.bundleRootURL = session.bundleRootURL
    self.log = log
  }

  // MARK: - Save / load

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
      log("[state:error] \(error.localizedDescription)")
    }
  }

  func persistSetupRun(_ setupRun: BundleSetupRunState) {
    bundleState.setupRun = setupRun
    persistBundleState()
  }

  // MARK: - View bindings

  func fieldBinding(for control: ControlSpec) -> Binding<String> {
    Binding(
      get: { self.fieldValues[control.id, default: control.value ?? ""] },
      set: { self.fieldValueChanged($0, for: control) }
    )
  }

  func checkedBinding(for control: ControlSpec) -> Binding<Set<String>> {
    Binding(
      get: {
        self.checkedOptions[
          control.id, default: Set(control.options.filter(\.selected).map(\.id))]
      },
      set: { self.checkedOptionsChanged($0, for: control) }
    )
  }
}
