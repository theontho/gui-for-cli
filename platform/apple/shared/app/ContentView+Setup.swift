import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#endif

extension ContentView {
  var activeSetupRun: BundleSetupRunState? {
    liveSetupRun ?? configStore.bundleState.setupRun
  }

  var applicableSetupSteps: [SetupStep] {
    manifest.setup.steps.filter { $0.applies() }
  }

  var shouldShowGlobalSetupStatusBar: Bool {
    guard !applicableSetupSteps.isEmpty else { return false }
    return activeSetupRun?.status != "ok"
  }

  var setupPromptMessage: String {
    var parts = [setupPromptBody]
    if let installSize = setupInitialInstallSizeMessage {
      parts.append(installSize)
    }
    if let diskSpace = setupDiskSpaceMessage {
      parts.append(diskSpace)
    }
    if let toolSummary = setupPromptToolSummary {
      parts.append(toolSummary)
    }
    return parts.joined(separator: "\n\n")
  }

  var setupPromptBody: String {
    let appName =
      manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? localizationLabels.setupPromptAppNameFallback
      : manifest.displayName
    return localizationLabels.setupPromptBodyFormat
      .replacingOccurrences(of: "%{app}", with: appName)
  }

  var setupPromptToolSummary: String? {
    applicableSetupSteps.compactMap {
      $0.setupToolSummary(labels: localizationLabels)
    }.first
  }

  var setupInitialInstallSizeMessage: String? {
    guard let sizeGB = setupInitialInstallSizeGB else { return nil }
    return localizationLabels.setupInitialInstallSizeFormat
      .replacingOccurrences(of: "%{size}", with: Self.formatSetupGB(sizeGB))
  }

  var setupDiskSpaceMessage: String? {
    setupPreflightResult?.message
  }

  var setupPreflightResult: ActionPrecheckResult? {
    guard let sizeGB = setupInitialInstallSizeGB else { return nil }
    return ActionPrecheckEvaluator.evaluate(
      spec: ActionPrecheckSpec(
        diskSpaceGB: String(sizeGB),
        diskSpacePath: "{{bundleRoot}}"),
      context: CommandRenderContext(bundleRootPath: bundleRootURL?.path),
      labels: localizationLabels)
  }

  private var setupInitialInstallSizeGB: Double? {
    guard let value = manifest.setup.initialInstallSizeGB,
      value.isFinite,
      value > 0
    else {
      return nil
    }
    return value
  }

  private var setupBlockingPreflight: ActionPrecheckResult? {
    guard let result = setupPreflightResult, result.severity == .warning else { return nil }
    return result
  }

  private static func formatSetupGB(_ value: Double) -> String {
    if value.rounded() == value {
      return String(format: "%.0f", value)
    }
    return String(format: value >= 10 ? "%.1f" : "%.2f", value)
  }

  func presentSetupPromptIfNeeded() {
    guard !hasPresentedSetupPrompt,
      !applicableSetupSteps.isEmpty,
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
    if let preflight = setupBlockingPreflight {
      let setupRun = BundleSetupRunState(
        status: "failed",
        completedAt: ISO8601DateFormatter().string(from: Date()),
        error: preflight.message)
      configStore.persistSetupRun(setupRun)
      terminal.appendToMain("[setup:error] \(preflight.message)")
      return
    }
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
