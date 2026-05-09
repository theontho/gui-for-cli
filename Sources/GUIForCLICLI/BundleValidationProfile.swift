import ArgumentParser
import Foundation
import GUIForCLICore

enum BundleValidationProfile: String, CaseIterable, ExpressibleByArgument {
  case development
  case release

  var localeWarningsAreErrors: Bool {
    self == .release
  }

  var allowsSkippingLocales: Bool {
    self == .development
  }

  func validationErrors(for loaded: LoadedBundle) -> [String] {
    var errors: [String] = []
    if self == .release, loaded.manifest.pageFiles.isEmpty {
      errors.append(
        "release profile requires `manifest.pages` to reference page files in `pages/*.json`; inline page objects are not allowed."
      )
    }
    return errors
  }
}
