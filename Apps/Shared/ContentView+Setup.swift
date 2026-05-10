import GUIForCLICore
import SwiftUI

extension ContentView {
  func runInitialSetupIfNeeded() {
    guard !hasAttemptedAutomaticSetup else { return }
    hasAttemptedAutomaticSetup = true
    guard !manifest.setup.steps.isEmpty, configStore.bundleState.setupRun == nil else { return }
    startBundleSetup()
  }

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
}
