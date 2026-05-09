import GUIForCLICore
import SwiftUI

extension ContentView {
  var settingsStandardOptionsAccessory: AnyView? {
    guard selectedPage.id == "settings" else {
      return nil
    }
    return AnyView(
      StandardOptionsSection(
        options: localizationOptions,
        labels: localizationLabels,
        selectedCode: selectedLocalizationCode,
        usingSystemDefault: usingSystemDefaultLocale,
        selectedIconSet: selectedIconSet,
        selectedColorTheme: selectedColorTheme,
        onSelectExplicit: { code in
          applyLocalization(code)
        },
        onSelectSystemDefault: { resetToSystemLocale() },
        onSelectIconSet: { iconSet in
          selectedIconSet = iconSet
          configStore.bundleState.iconSet = iconSet
          configStore.persistBundleState()
        },
        onSelectColorTheme: { colorTheme in
          selectedColorTheme = colorTheme
          configStore.bundleState.colorTheme = colorTheme
          configStore.persistBundleState()
        }))
  }

  func resetToSystemLocale() {
    configStore.bundleState.localizationCode = nil
    configStore.persistBundleState()
    usingSystemDefaultLocale = true
    let match =
      BundleSourceLoader.matchLocalizationCode(
        preferences: BundleSessionLoader.systemPreferredLocalizations(),
        options: localizationOptions) ?? BundleSourceLoader.defaultLocalizationCode
    if match != selectedLocalizationCode {
      applyLocalization(match, persist: false)
    }
  }

  func applyLocalization(_ code: String, persist: Bool = true) {
    guard let bundleSourceRootURL else { return }

    do {
      let loadedBundle = try BundleSourceLoader().load(
        from: bundleSourceRootURL,
        localizationCode: code)
      manifest = loadedBundle.manifest
      localizationOptions = loadedBundle.localizationOptions
      localizationLabels = loadedBundle.localizationLabels
      if selectedLocalizationCode != loadedBundle.localizationCode {
        selectedLocalizationCode = loadedBundle.localizationCode
      }
      terminal.updateExitCodeReference(loadedBundle.manifest.effectiveExitCodeReference)
      terminal.updateLocalizationLabels(loadedBundle.localizationLabels)
      if persist {
        configStore.bundleState.localizationCode = loadedBundle.localizationCode
        configStore.persistBundleState()
        usingSystemDefaultLocale = false
      }
      if selectedPageID.flatMap({ id in loadedBundle.manifest.pages.first { $0.id == id } }) == nil
      {
        selectedPageID = loadedBundle.manifest.pages.first?.id
      }
    } catch {
      terminal.appendToMain("[localization:error] \(error.localizedDescription)")
    }
  }

  /// Re-resolves the active localization when the system locale changes. Honors
  /// any locale the user has explicitly chosen via the in-app picker (recorded
  /// in the workspace `state.json`) and otherwise falls back to the new best
  /// system match without persisting it.
  func systemLocaleDidChange() {
    if configStore.bundleState.localizationCode != nil { return }
    guard
      let match = BundleSourceLoader.matchLocalizationCode(
        preferences: BundleSessionLoader.systemPreferredLocalizations(),
        options: localizationOptions),
      match != selectedLocalizationCode
    else { return }
    applyLocalization(match, persist: false)
  }
}

extension BundleColorTheme {
  var swiftUIColorScheme: ColorScheme? {
    switch self {
    case .system:
      return nil
    case .light:
      return .light
    case .dark:
      return .dark
    }
  }
}
