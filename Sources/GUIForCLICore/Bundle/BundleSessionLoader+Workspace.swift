import Foundation

public extension BundleSessionLoader {
  /// Best-effort: copy bundle contents into a per-bundle workspace under
  /// Application Support, preserving local runtime state. Falls back to the
  /// in-place source if the workspace can't be prepared.
  static func prepareBundleWorkspace(
    for manifest: CLIBundleManifest,
    sourceRootURL: URL
  ) -> (rootURL: URL, messages: [String]) {
    let workspaceURL = AppPaths.bundleWorkspaceDirectory(for: manifest.id)
    do {
      try BundleSourceLoader().syncBundleWorkspace(from: sourceRootURL, to: workspaceURL)
      return (
        workspaceURL,
        ["[bundle] Using persistent workspace: \(workspaceURL.path)"]
      )
    } catch {
      return (
        sourceRootURL,
        [
          "[bundle:error] Could not prepare persistent workspace: \(error.localizedDescription)",
          "[bundle] Falling back to bundle source: \(sourceRootURL.path)",
        ]
      )
    }
  }

  /// System-preferred locale identifiers, in priority order. Combines
  /// `Locale.preferredLanguages` and the current locale identifier so we
  /// pick up both UI language and region overrides.
  static func systemPreferredLocalizations() -> [String] {
    var seen: Set<String> = []
    var ordered: [String] = []
    for raw in Locale.preferredLanguages + [Locale.current.identifier] {
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
      ordered.append(trimmed)
    }
    return ordered
  }
}
