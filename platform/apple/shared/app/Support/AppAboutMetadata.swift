#if os(macOS)
  import AppKit
  import Combine
  import Foundation
  import GUIForCLICore

  @MainActor
  final class AppAboutMetadata: ObservableObject {
    private struct VersionDetails {
      var guiForCLIVersion: String?
      var bundleVersion: String?
      var toolVersion: String?
    }

    private static let githubURLString = "https://github.com/theontho/gui-for-cli"
    private static let license = "MIT License"
    private static let unspecifiedValue = "Not specified"
    private static var githubURL: URL {
      guard let url = URL(string: githubURLString) else {
        preconditionFailure("Invalid GitHub URL: \(githubURLString)")
      }
      return url
    }
    private static let copyrightOptionKey = NSApplication.AboutPanelOptionKey(rawValue: "Copyright")

    @Published private var details: VersionDetails

    init(
      appVersion: String? = AppVersion.current,
      manifest: CLIBundleManifest = DemoBundle.defaultManifest
    ) {
      details = Self.versionDetails(appVersion: appVersion, manifest: manifest)
    }

    func update(appVersion: String? = AppVersion.current, session: BundleSession) {
      details = Self.versionDetails(appVersion: appVersion, manifest: session.manifest)
    }

    func aboutPanelOptions(applicationName: String) -> [NSApplication.AboutPanelOptionKey: Any] {
      [
        .applicationName: applicationName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
          ?? "GUI for CLI",
        .applicationVersion: display(details.guiForCLIVersion),
        .credits: credits,
        Self.copyrightOptionKey: Self.license,
      ]
    }

    private static func versionDetails(
      appVersion: String?,
      manifest: CLIBundleManifest
    ) -> VersionDetails {
      VersionDetails(
        guiForCLIVersion: normalized(appVersion),
        bundleVersion: normalized(manifest.version),
        toolVersion: toolVersion(in: manifest))
    }

    private static func toolVersion(in manifest: CLIBundleManifest) -> String? {
      for step in manifest.setup.steps + manifest.uninstall.steps {
        guard let version = normalized(step.toolVersion) else { continue }
        guard let toolName = normalized(step.toolName) else { return version }
        return "\(toolName) \(version)"
      }
      return nil
    }

    private static func normalized(_ value: String?) -> String? {
      value?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    private func display(_ value: String?) -> String {
      value ?? Self.unspecifiedValue
    }

    private var credits: NSAttributedString {
      let text = [
        "GUI for CLI version: \(display(details.guiForCLIVersion))",
        "Bundle version: \(display(details.bundleVersion))",
        "Tool version: \(display(details.toolVersion))",
        "",
        "GitHub: \(Self.githubURLString)",
      ].joined(separator: "\n")
      let credits = NSMutableAttributedString(string: text)
      let fullRange = NSRange(location: 0, length: credits.length)
      credits.addAttributes(
        [
          .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
          .foregroundColor: NSColor.labelColor,
        ],
        range: fullRange)
      if let range = text.range(of: Self.githubURLString) {
        credits.addAttribute(.link, value: Self.githubURL, range: NSRange(range, in: text))
      }
      return credits
    }
  }
#endif
