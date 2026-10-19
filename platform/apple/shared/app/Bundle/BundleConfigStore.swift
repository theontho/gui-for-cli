import Foundation
import GUIForCLICore
import Observation
import SwiftUI

/// Owns the mutable per-bundle configuration state (form values, checkbox
/// selections, bound TOML config values, on-disk paths) plus the
/// persistence layer that mirrors them into the bundle's workspace
/// `state.json` and bound config files. Shared through the SwiftUI
/// environment so renderers don't thread bindings and closures around.
///
/// Writes are debounced: typing marks state dirty and the files are written
/// once input pauses, or immediately via `flushPendingWrites()` on teardown.
@MainActor
@Observable
final class BundleConfigStore {
  static let defaultPersistenceDelay: Duration = .milliseconds(500)

  var fieldValues: [String: String]
  var checkedOptions: [String: Set<String>]
  var configValues: [String: String]
  var configFilePaths: [String: String]
  var bundleState: BundleState

  /// Latest manifest in effect. Not observed: re-renders are driven by
  /// ContentView's own `@State manifest`; the store reads it on demand to
  /// look up config-setting bindings against the current page graph.
  @ObservationIgnored var manifest: CLIBundleManifest

  @ObservationIgnored let bundleStateStore: BundleStateStore?
  @ObservationIgnored let bundleRootURL: URL?
  /// Sink for user-facing diagnostic lines (errors, save/load receipts).
  /// Injected to avoid coupling the store to `TerminalLogStore` directly.
  @ObservationIgnored private let log: (String) -> Void
  @ObservationIgnored private let persistenceDelay: Duration
  @ObservationIgnored private var hasPendingStateWrite = false
  @ObservationIgnored private var pendingConfigSaves: [String: ControlSpec] = [:]
  @ObservationIgnored private var flushTask: Task<Void, Never>?
  @ObservationIgnored private var isPersistenceStopped = false

  init(
    session: BundleSession,
    persistenceDelay: Duration = BundleConfigStore.defaultPersistenceDelay,
    log: @escaping (String) -> Void
  ) {
    self.fieldValues = session.fieldValues
    self.checkedOptions = session.checkedOptions
    self.configValues = session.configValues
    self.configFilePaths = session.configFilePaths
    self.bundleState = session.bundleState
    self.manifest = session.manifest
    self.bundleStateStore = session.bundleStateStore
    self.bundleRootURL = session.bundleRootURL
    self.persistenceDelay = persistenceDelay
    self.log = log
  }

  // MARK: - Save / load

  /// Queues a write of `control`'s bound config file.
  func saveConfig(_ control: ControlSpec) {
    pendingConfigSaves[control.id] = control
    scheduleFlush()
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
      saveConfig(binding.control)
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
      saveConfig(binding.control)
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
    saveConfig(control)
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

  /// Queues a write of `state.json`.
  func persistBundleState() {
    hasPendingStateWrite = true
    scheduleFlush()
  }

  /// Drops queued writes and ignores later ones, so an uninstalled app's
  /// teardown doesn't recreate the workspace it just removed.
  func stopPersisting() {
    flushTask?.cancel()
    flushTask = nil
    hasPendingStateWrite = false
    pendingConfigSaves.removeAll()
    isPersistenceStopped = true
  }

  /// Writes all queued state and config files now.
  func flushPendingWrites() {
    flushTask?.cancel()
    flushTask = nil
    guard !isPersistenceStopped else { return }
    if hasPendingStateWrite, let bundleStateStore {
      do {
        try bundleStateStore.save(bundleState)
      } catch {
        log("[state:error] \(error.localizedDescription)")
      }
    }
    hasPendingStateWrite = false
    let controls = pendingConfigSaves.values
    pendingConfigSaves.removeAll()
    for control in controls {
      BundleConfigFileActions.saveConfig(
        control,
        configURL: resolvedConfigURL(for: control),
        reportSuccess: false,
        settingValueProvider: { configSettingValue(for: $0, in: control) },
        log: log)
    }
  }

  private func scheduleFlush() {
    flushTask?.cancel()
    flushTask = Task { [weak self, persistenceDelay] in
      try? await Task.sleep(for: persistenceDelay)
      guard !Task.isCancelled else { return }
      self?.flushPendingWrites()
    }
  }

  func persistSetupRun(_ setupRun: BundleSetupRunState) {
    bundleState.setupRun = setupRun
    hasPendingStateWrite = true
    flushPendingWrites()
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
