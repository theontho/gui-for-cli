import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#endif

extension ContentView {
  func startBundleSetup() {
    guard !isSetupRunning else { return }
    guard let bundleRootURL else {
      terminal.appendToMain("[setup:error] Missing bundle workspace.")
      return
    }
    do {
      let commands = try SetupCommandPlanner().plan(for: manifest, rootURL: bundleRootURL)
      isSetupRunning = true
      runningSetupStepID = nil
      liveSetupRun = BundleSetupRunState(status: "running")
      terminal.startSetup(
        commands,
        onStepStart: { command in
          runningSetupStepID = command.id
        },
        onStepComplete: { stepResult in
          var current = liveSetupRun ?? BundleSetupRunState(status: "running")
          current.results.removeAll { $0.id == stepResult.id }
          current.results.append(stepResult)
          current.status = "running"
          liveSetupRun = current
          runningSetupStepID = nil
        },
        onComplete: { setupRun in
          isSetupRunning = false
          runningSetupStepID = nil
          liveSetupRun = nil
          configStore.persistSetupRun(setupRun)
        })
    } catch {
      isSetupRunning = false
      runningSetupStepID = nil
      liveSetupRun = nil
      let setupRun = BundleSetupRunState(
        status: "failed",
        completedAt: ISO8601DateFormatter().string(from: Date()),
        error: error.localizedDescription)
      configStore.persistSetupRun(setupRun)
      terminal.appendToMain("[setup:error] \(error.localizedDescription)")
    }
  }

  func openBundleWorkspace() {
    guard let bundleRootURL else {
      terminal.appendToMain("[bundle:error] Missing bundle workspace.")
      return
    }
    #if os(macOS)
      NSWorkspace.shared.open(bundleRootURL)
    #else
      terminal.appendToMain("[bundle] \(bundleRootURL.path)")
    #endif
  }
}
