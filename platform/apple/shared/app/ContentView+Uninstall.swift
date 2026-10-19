import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit

  /// Outcome of an uninstall, written to `GUI_FOR_CLI_UNINSTALL_RESULT_FILE`.
  struct BundleUninstallResult: Codable {
    var status: String
    var steps: BundleSetupRunState?
    var log: [String]
  }

  extension ContentView {
    static var autoRunsUninstall: Bool {
      ProcessInfo.processInfo.environment["GUI_FOR_CLI_AUTO_RUN_UNINSTALL"] == "1"
    }

    var uninstallConfirmationMessage: String {
      String(
        localized:
          "This runs the bundle's uninstall steps, deletes everything \(manifest.displayName) keeps in your Library (including downloaded reference genomes and settings stored in the app's workspace), and moves the app to the Trash. Files you saved elsewhere are kept."
      )
    }

    func startAutomatedUninstallIfNeeded() {
      guard !hasStartedAutomatedUninstall else { return }
      hasStartedAutomatedUninstall = true
      terminal.appendToMain(
        "[uninstall:auto] Starting uninstall from GUI_FOR_CLI_AUTO_RUN_UNINSTALL.")
      startBundleUninstall()
    }

    func startBundleUninstall() {
      guard !isSetupRunning, !isUninstallRunning else { return }
      guard let bundleRootURL else {
        finishUninstall(BundleUninstallResult(status: "failed", log: ["Missing bundle workspace."]))
        return
      }
      let commands: [SetupCommand]
      do {
        commands = try SetupCommandPlanner().planUninstall(for: manifest, rootURL: bundleRootURL)
      } catch {
        finishUninstall(
          BundleUninstallResult(status: "failed", log: [error.localizedDescription]))
        return
      }
      isUninstallRunning = true
      guard !commands.isEmpty else {
        removeAppDataAndQuit(steps: nil)
        return
      }
      terminal.startSetup(
        commands,
        labels: localizationLabels,
        onComplete: { run in
          guard run.status == "ok" else {
            isUninstallRunning = false
            // Keep the app and its data so the user can retry or inspect the log.
            finishUninstall(
              BundleUninstallResult(
                status: "failed", steps: run,
                log: ["Uninstall steps failed; app data was kept."]))
            return
          }
          removeAppDataAndQuit(steps: run)
        })
    }

    private func removeAppDataAndQuit(steps: BundleSetupRunState?) {
      configStore.stopPersisting()
      terminal.terminateAll()
      var log = AppUninstaller.removeAppData()
      AppUninstaller.moveAppToTrash { line in
        log.append(line)
        let failed = log.contains { $0.hasPrefix("[uninstall:error]") }
        finishUninstall(
          BundleUninstallResult(status: failed ? "failed" : "ok", steps: steps, log: log))
        NSApplication.shared.terminate(nil)
      }
    }

    private func finishUninstall(_ result: BundleUninstallResult) {
      for line in result.log {
        terminal.appendToMain(line)
      }
      guard
        let path = ProcessInfo.processInfo.environment["GUI_FOR_CLI_UNINSTALL_RESULT_FILE"],
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return }
      let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? encoder.encode(result).write(to: url, options: .atomic)
    }
  }
#endif

/// Uninstalls the focused window's bundle and the app (macOS menu command).
struct UninstallBundleAction {
  let run: @MainActor () -> Void

  @MainActor func callAsFunction() {
    run()
  }
}

private struct UninstallBundleActionKey: FocusedValueKey {
  typealias Value = UninstallBundleAction
}

extension FocusedValues {
  var uninstallBundle: UninstallBundleAction? {
    get { self[UninstallBundleActionKey.self] }
    set { self[UninstallBundleActionKey.self] = newValue }
  }
}
