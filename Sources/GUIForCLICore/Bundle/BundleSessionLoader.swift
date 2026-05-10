import Foundation

/// Bootstrapped per-bundle session state, ready to seed `ContentView`.
public struct BundleSession {
  public var manifest: CLIBundleManifest
  public var localizationOptions: [BundleLocalizationOption]
  public var localizationLabels: BundleLocalizationLabels
  public var localizationCode: String
  public var usingSystemDefaultLocale: Bool
  public var bundleRootURL: URL
  public var bundleState: BundleState
  public var bundleStateStore: BundleStateStore
  public var configFilePaths: [String: String]
  public var configValues: [String: String]
  public var fieldValues: [String: String]
  public var checkedOptions: [String: Set<String>]
  public var startupMessages: [String]
}

/// Loads, prepares the workspace, applies state, and produces a `BundleSession`
/// in one place so `ContentView.init` doesn't have to orchestrate it.
public enum BundleSessionLoader {
  public static func bootstrap(
    sourceRootURL: URL,
    fallbackManifest: CLIBundleManifest,
    systemPreferences: [String]
  ) -> BundleSession {
    let defaultLoaded = try? BundleSourceLoader().load(from: sourceRootURL)
    let workspace = prepareBundleWorkspace(
      for: defaultLoaded?.manifest ?? fallbackManifest,
      sourceRootURL: sourceRootURL)
    let stateStore = BundleStateStore(workspaceURL: workspace.rootURL)
    var bundleState = stateStore.load()

    let storedLocalizationCode = bundleState.localizationCode
    let availableOptions = defaultLoaded?.localizationOptions ?? []
    let resolvedRequest =
      storedLocalizationCode
      ?? BundleSourceLoader.matchLocalizationCode(
        preferences: systemPreferences,
        options: availableOptions)
    let loaded =
      if resolvedRequest == nil || resolvedRequest == BundleSourceLoader.defaultLocalizationCode {
        defaultLoaded
      } else {
        try? BundleSourceLoader().load(
          from: sourceRootURL,
          localizationCode: resolvedRequest)
      }
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
