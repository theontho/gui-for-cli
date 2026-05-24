import Foundation
import GUIForCLICore

enum AppVersion {
  static var current: String? {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return version?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
  }

  static func windowTitle(_ title: String) -> String {
    guard let current else {
      return title
    }
    return "\(title) - \(current)"
  }
}
