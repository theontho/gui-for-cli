import GUIForCLICore
import SwiftUI

struct CommandRenderContextKey: EnvironmentKey {
  static let defaultValue = CommandRenderContext()
}

struct BundleLocalizationLabelsKey: EnvironmentKey {
  static let defaultValue = BundleLocalizationLabels()
}

extension EnvironmentValues {
  var commandRenderContext: CommandRenderContext {
    get { self[CommandRenderContextKey.self] }
    set { self[CommandRenderContextKey.self] = newValue }
  }

  var bundleLocalizationLabels: BundleLocalizationLabels {
    get { self[BundleLocalizationLabelsKey.self] }
    set { self[BundleLocalizationLabelsKey.self] = newValue }
  }
}
