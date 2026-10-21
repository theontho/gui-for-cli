#if os(macOS)
  import AppKit
  import GUIForCLICore

  /// Removes what the app keeps outside its own bundle, then moves the app to
  /// the Trash. Bundle uninstall steps (runtimes, tools) run before this.
  @MainActor
  enum AppUninstaller {
    /// Per-user locations the app or macOS create for it. With an app-data
    /// name override (development and tests) only that isolated folder counts,
    /// so a test never deletes the real app's preferences or caches.
    static func dataLocations(
      bundleID: String? = Bundle.main.bundleIdentifier,
      environment: [String: String] = ProcessInfo.processInfo.environment,
      fileManager: FileManager = .default
    ) -> [URL] {
      var locations = [AppPaths.appSupportDirectory(environment: environment)]
      let hasOverride = !(environment[AppPaths.appSupportNameEnvironmentKey] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      guard let bundleID, !hasOverride else { return locations }
      let library =
        fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
      locations += [
        library.appendingPathComponent("Caches/\(bundleID)"),
        library.appendingPathComponent("HTTPStorages/\(bundleID)"),
        library.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"),
        library.appendingPathComponent("WebKit/\(bundleID)"),
        library.appendingPathComponent("Saved Application State/\(bundleID).savedState"),
        library.appendingPathComponent("Preferences/\(bundleID).plist"),
      ]
      return locations
    }

    /// Returns one log line per location removed or failed.
    static func removeAppData(fileManager: FileManager = .default) -> [String] {
      // Flush window/split-view layout defaults before deleting their domain.
      // Otherwise the asynchronous Trash operation can let a pending layout recreate it.
      for window in NSApplication.shared.windows {
        window.close()
      }
      let locations = dataLocations(fileManager: fileManager)
      if let bundleID = Bundle.main.bundleIdentifier, locations.count > 1 {
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
      }
      return locations.compactMap { url in
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
          try fileManager.removeItem(at: url)
          return "[uninstall] Removed \(url.path)"
        } catch {
          return "[uninstall:error] Could not remove \(url.path): \(error.localizedDescription)"
        }
      }
    }

    /// Moves the running app to the Trash, as dragging it there would.
    static func moveAppToTrash(completion: @escaping @MainActor (String) -> Void) {
      let appURL = Bundle.main.bundleURL
      guard appURL.pathExtension == "app" else {
        completion("[uninstall] Not running from an app bundle; leaving \(appURL.path)")
        return
      }
      NSWorkspace.shared.recycle([appURL]) { _, error in
        Task { @MainActor in
          if let error {
            completion(
              "[uninstall:error] Could not move \(appURL.path) to the Trash: \(error.localizedDescription)"
            )
          } else {
            completion("[uninstall] Moved \(appURL.path) to the Trash")
          }
        }
      }
    }
  }
#endif
