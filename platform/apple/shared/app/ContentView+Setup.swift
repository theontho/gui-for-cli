import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#endif

extension ContentView {
  var activeSetupRun: BundleSetupRunState? {
    liveSetupRun ?? configStore.bundleState.setupRun
  }

  var shouldShowGlobalSetupStatusBar: Bool {
    guard !manifest.setup.steps.isEmpty else { return false }
    return activeSetupRun?.status != "ok"
  }

  var setupPromptMessage: String {
    let appName =
      manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? localizationLabels.setupPromptAppNameFallback
      : manifest.displayName
    let body = localizationLabels.setupPromptBodyFormat
      .replacingOccurrences(of: "%{app}", with: appName)
    let toolSummary = manifest.setup.steps.compactMap {
      $0.setupToolSummary(labels: localizationLabels)
    }.first
    guard let toolSummary else { return body }
    return "\(body)\n\n\(toolSummary)"
  }

  func presentSetupPromptIfNeeded() {
    guard !hasPresentedSetupPrompt,
      !manifest.setup.steps.isEmpty,
      configStore.bundleState.setupRun == nil
    else { return }
    hasPresentedSetupPrompt = true
    isSetupPromptPresented = true
  }

  func goToSetupAndStart() {
    selectedPageID = setupPageID
    persistSelectedPageID(selectedPageID)
    guard !isSetupRunning else { return }
    startBundleSetup()
  }

  private var setupPageID: String? {
    manifest.pages.first { $0.id == "settings" }?.id ?? manifest.pages.first?.id
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
