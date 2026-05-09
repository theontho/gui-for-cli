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
}
