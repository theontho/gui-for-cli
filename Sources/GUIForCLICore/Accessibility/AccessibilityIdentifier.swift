import Foundation

/// Stable, locale-independent accessibility identifiers derived from
/// manifest IDs.
///
/// These strings are surfaced via SwiftUI's `accessibilityIdentifier`
/// modifier and consumed by:
///   * VoiceOver / Switch Control rotors (via "axe describe-ui")
///   * Future XCUITest suites that need a stable handle on a specific
///     control regardless of the active locale
///
/// IDs follow `<namespace>.<id>` (or `option.<controlID>.<optionID>`)
/// so they group naturally in flat dumps. Keep them ASCII-only.
public enum AccessibilityIdentifier {
  public static func page(_ id: String) -> String { "page.\(id)" }
  public static func section(_ id: String) -> String { "section.\(id)" }
  public static func control(_ id: String) -> String { "control.\(id)" }
  public static func action(_ id: String) -> String { "action.\(id)" }
  public static func option(controlID: String, optionID: String) -> String {
    "option.\(controlID).\(optionID)"
  }
  public static func chooser(controlID: String) -> String {
    "control.\(controlID).choose"
  }
  public static func info(controlID: String) -> String {
    "control.\(controlID).info"
  }
}
