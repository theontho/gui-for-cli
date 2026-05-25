import Foundation

public struct BundleTestRunnerOptions: Sendable {
  public var workspaceURL: URL?
  public var dryRun: Bool
  public var prepareWorkspace: Bool
  public var bootstrapConfig: Bool
  public var localizationCode: String?
  public var progressHandler: (@Sendable (BundleTestProgressEvent) -> Void)?

  public init(
    workspaceURL: URL? = nil,
    dryRun: Bool = false,
    prepareWorkspace: Bool = true,
    bootstrapConfig: Bool = true,
    localizationCode: String? = nil,
    progressHandler: (@Sendable (BundleTestProgressEvent) -> Void)? = nil
  ) {
    self.workspaceURL = workspaceURL
    self.dryRun = dryRun
    self.prepareWorkspace = prepareWorkspace
    self.bootstrapConfig = bootstrapConfig
    self.localizationCode = localizationCode
    self.progressHandler = progressHandler
  }
}

public enum BundleTestProgressEvent: Sendable {
  case message(String)
  case commandOutput(String)
}

public struct BundleTestRunner: Sendable {
  private let processRunner: BundleTestProcessRunner

  public init(processRunner: BundleTestProcessRunner = BundleTestProcessRunner()) {
    self.processRunner = processRunner
  }

  public func run(
    bundleURL: URL,
    plan: BundleTestPlan,
    options: BundleTestRunnerOptions = BundleTestRunnerOptions()
  ) throws -> BundleTestReport {
    let startedAt = Self.timestamp()
    let loaded = try BundleSourceLoader().load(
      from: bundleURL, localizationCode: options.localizationCode)
    let workspace = try prepareWorkspace(
      loaded: loaded,
      explicitWorkspaceURL: options.workspaceURL,
      shouldPrepare: options.prepareWorkspace)
    let activeBundle = try BundleSourceLoader().load(
      from: workspace.rootURL,
      localizationCode: options.localizationCode)
    let runtime = try makeRuntime(
      manifest: activeBundle.manifest,
      rootURL: workspace.rootURL,
      bootstrapConfig: options.bootstrapConfig,
      planInputs: plan.inputs)
    let progress = options.progressHandler
    let planName = plan.name ?? activeBundle.manifest.displayName
    emit(
      .message("Bundle test started: \(planName) (\(plan.steps.count) steps)"),
      to: progress)
    for message in workspace.messages + runtime.messages {
      emit(.message(message), to: progress)
    }

    var reports: [BundleTestStepReport] = []
    var shouldSkipRemaining = false
    for (offset, step) in plan.steps.enumerated() {
      let index = offset + 1
      if shouldSkipRemaining {
        emit(
          .message("Step \(index)/\(plan.steps.count) skipped after a previous failure."),
          to: progress)
        let report = skippedReport(
          step: step,
          index: index,
          reason: "Skipped after a previous failure.")
        reports.append(report)
        continue
      }

      emit(
        .message("Step \(index)/\(plan.steps.count) started: \(stepDescription(step))"),
        to: progress)
      let report = try runStep(
        step,
        index: index,
        manifest: activeBundle.manifest,
        rootURL: workspace.rootURL,
        runtime: runtime,
        dryRun: options.dryRun,
        progressHandler: progress)
      reports.append(report)
      emitStepFinished(report, totalSteps: plan.steps.count, to: progress)
      if report.status == .failed && !step.continueOnFailure {
        shouldSkipRemaining = true
      }
    }

    let summary = BundleTestSummary(
      total: reports.count,
      passed: reports.filter { $0.status == .passed }.count,
      failed: reports.filter { $0.status == .failed }.count,
      skipped: reports.filter { $0.status == .skipped }.count)
    return BundleTestReport(
      planName: plan.name,
      bundleID: activeBundle.manifest.id,
      bundleName: activeBundle.manifest.displayName,
      bundleVersion: activeBundle.manifest.version,
      bundleRoot: workspace.rootURL.path,
      status: summary.failed == 0 ? .passed : .failed,
      startedAt: startedAt,
      finishedAt: Self.timestamp(),
      summary: summary,
      messages: workspace.messages + runtime.messages,
      steps: reports)
  }

  private func prepareWorkspace(
    loaded: LoadedBundle,
    explicitWorkspaceURL: URL?,
    shouldPrepare: Bool
  ) throws -> (rootURL: URL, messages: [String]) {
    if let explicitWorkspaceURL {
      try BundleSourceLoader().syncBundleWorkspace(
        from: loaded.rootURL,
        to: explicitWorkspaceURL,
        requiringManagedDestination: true)
      return (
        explicitWorkspaceURL,
        ["[bundle] Using test workspace: \(explicitWorkspaceURL.path)"]
      )
    }

    guard shouldPrepare else {
      return (loaded.rootURL, ["[bundle] Using bundle source: \(loaded.rootURL.path)"])
    }

    return BundleSessionLoader.prepareBundleWorkspace(
      for: loaded.manifest,
      sourceRootURL: loaded.rootURL)
  }

  private func makeRuntime(
    manifest: CLIBundleManifest,
    rootURL: URL,
    bootstrapConfig: Bool,
    planInputs: BundleTestInputs
  ) throws -> BundleTestRuntime {
    var state = BundleState()
    let configFilePaths = BundleSessionLoader.initialConfigFilePaths(for: manifest, state: &state)
    var messages: [String] = []
    if bootstrapConfig {
      messages += BundleSessionLoader.bootstrapConfigFiles(
        for: manifest,
        rootURL: rootURL,
        configFilePaths: configFilePaths)
    }
    let initialConfig = BundleSessionLoader.initialConfigValues(
      for: manifest,
      rootURL: rootURL,
      configFilePaths: configFilePaths)
    messages += initialConfig.messages

    let baseInputs = BundleTestInputs(
      fieldValues: BundleSessionLoader.initialFieldValues(
        for: manifest,
        configValues: initialConfig.values,
        state: state),
      configValues: initialConfig.values,
      checkedOptions: BundleSessionLoader.initialCheckedOptions(
        for: manifest,
        configValues: initialConfig.values,
        state: state
      ).mapValues { $0.sorted() }
    ).merging(planInputs)
      .expandingBundlePaths(rootURL: rootURL)
    return BundleTestRuntime(inputs: baseInputs, messages: messages)
  }

  private func runStep(
    _ step: BundleTestStep,
    index: Int,
    manifest: CLIBundleManifest,
    rootURL: URL,
    runtime: BundleTestRuntime,
    dryRun: Bool,
    progressHandler: (@Sendable (BundleTestProgressEvent) -> Void)?
  ) throws -> BundleTestStepReport {
    switch step.kind {
    case .setup:
      return try runSetupStep(
        step,
        index: index,
        manifest: manifest,
        rootURL: rootURL,
        dryRun: dryRun,
        progressHandler: progressHandler)
    case .action:
      return try runActionStep(
        step,
        index: index,
        manifest: manifest,
        rootURL: rootURL,
        runtime: runtime,
        dryRun: dryRun,
        progressHandler: progressHandler)
    }
  }

  private func runSetupStep(
    _ step: BundleTestStep,
    index: Int,
    manifest: CLIBundleManifest,
    rootURL: URL,
    dryRun: Bool,
    progressHandler: (@Sendable (BundleTestProgressEvent) -> Void)?
  ) throws -> BundleTestStepReport {
    let started = Date()
    let startedAt = Self.timestamp(started)
    let commands = try SetupCommandPlanner(requireScriptFiles: !dryRun).plan(
      for: manifest,
      rootURL: rootURL)
    var output = ""
    var exitCode: Int32 = 0
    var timedOut = false
    var error: String?

    for command in commands {
      let commandHeader = "==> \(command.label)\n$ \(command.displayCommand)\n"
      output += commandHeader
      emit(.message(commandHeader.trimmingCharacters(in: .newlines)), to: progressHandler)
      guard !dryRun else { continue }
      let result = try processRunner.run(
        command: command,
        timeoutSeconds: step.timeoutSeconds,
        onOutput: { emit(.commandOutput($0), to: progressHandler) })
      output += result.output
      if !result.output.hasSuffix("\n"), !result.output.isEmpty {
        output += "\n"
      }
      if result.timedOut {
        timedOut = true
        error = "Setup command timed out: \(command.label)"
        break
      }
      if result.exitStatus != 0 {
        exitCode = result.exitStatus
        if command.optional {
          output += "Optional setup step failed with exit code \(result.exitStatus).\n"
        } else {
          error = "Setup command failed with exit code \(result.exitStatus): \(command.label)"
          break
        }
      }
    }

    if !dryRun, error == nil {
      error = outputExpectationFailure(output: output, step: step)
    }
    let status = dryRun ? BundleTestStatus.skipped : (error == nil ? .passed : .failed)
    return makeReport(
      step: step,
      index: index,
      started: started,
      startedAt: startedAt,
      status: status,
      command: "bundle setup (\(commands.count) step\(commands.count == 1 ? "" : "s"))",
      exitCode: dryRun || timedOut ? nil : exitCode,
      timedOut: timedOut,
      output: output,
      error: error)
  }

  private func runActionStep(
    _ step: BundleTestStep,
    index: Int,
    manifest: CLIBundleManifest,
    rootURL: URL,
    runtime: BundleTestRuntime,
    dryRun: Bool,
    progressHandler: (@Sendable (BundleTestProgressEvent) -> Void)?
  ) throws -> BundleTestStepReport {
    let started = Date()
    let startedAt = Self.timestamp(started)
    do {
      let resolved = try resolveAction(
        step: step, manifest: manifest, rootURL: rootURL, runtime: runtime)
      let missing = resolved.action.command.missingPlaceholders(resolving: resolved.context)
      guard missing.isEmpty else {
        return makeReport(
          step: step,
          index: index,
          started: started,
          startedAt: startedAt,
          status: .failed,
          command: nil,
          output: "",
          error: "Missing input values: \(missing.joined(separator: ", "))")
      }
      guard resolved.action.isVisible(resolving: resolved.context) else {
        return makeReport(
          step: step,
          index: index,
          started: started,
          startedAt: startedAt,
          status: .failed,
          command: nil,
          output: "",
          error: "Action is not visible for the provided inputs.")
      }
      if let disabledReason = resolved.action.disabledReason(resolving: resolved.context) {
        return makeReport(
          step: step,
          index: index,
          started: started,
          startedAt: startedAt,
          status: .failed,
          command: nil,
          output: "",
          error: "Action is disabled: \(disabledReason)")
      }

      let command = resolved.action.command.renderedCommand(resolving: resolved.context)
      emit(.message("$ \(command.displayCommand)"), to: progressHandler)
      guard !dryRun else {
        return makeReport(
          step: step,
          index: index,
          started: started,
          startedAt: startedAt,
          status: .skipped,
          command: command.displayCommand,
          output: "",
          error: nil)
      }

      let result = try processRunner.run(
        command: command,
        workingDirectory: rootURL,
        timeoutSeconds: step.timeoutSeconds,
        onOutput: { emit(.commandOutput($0), to: progressHandler) })
      var error: String?
      if result.timedOut {
        error = "Action timed out."
      } else if !step.expectedExitCodes.contains(result.exitStatus) {
        error =
          "Expected exit code \(step.expectedExitCodes.map(String.init).joined(separator: ", ")) but got \(result.exitStatus)."
      }
      if error == nil {
        error = outputExpectationFailure(output: result.output, step: step)
      }
      return makeReport(
        step: step,
        index: index,
        started: started,
        startedAt: startedAt,
        status: error == nil ? .passed : .failed,
        command: command.displayCommand,
        exitCode: result.exitStatus,
        timedOut: result.timedOut,
        output: result.output,
        error: error)
    } catch {
      return makeReport(
        step: step,
        index: index,
        started: started,
        startedAt: startedAt,
        status: .failed,
        command: nil,
        output: "",
        error: error.localizedDescription)
    }
  }

  private func outputExpectationFailure(output: String, step: BundleTestStep) -> String? {
    var failures: [String] = []
    for required in step.requiredOutput where !output.contains(required) {
      failures.append("Required output was not found: \(required)")
    }
    for forbidden in step.forbiddenOutput where output.contains(forbidden) {
      failures.append("Forbidden output was found: \(forbidden)")
    }
    return failures.isEmpty ? nil : failures.joined(separator: " ")
  }

  private func makeReport(
    step: BundleTestStep,
    index: Int,
    started: Date,
    startedAt: String,
    status: BundleTestStatus,
    command: String?,
    exitCode: Int32? = nil,
    timedOut: Bool = false,
    output: String,
    error: String?
  ) -> BundleTestStepReport {
    let finished = Date()
    return BundleTestStepReport(
      index: index,
      id: step.id,
      kind: step.kind,
      actionID: step.actionID,
      status: status,
      command: command,
      exitCode: exitCode,
      timedOut: timedOut,
      startedAt: startedAt,
      finishedAt: Self.timestamp(finished),
      durationSeconds: finished.timeIntervalSince(started),
      output: output,
      error: error)
  }

  private func skippedReport(step: BundleTestStep, index: Int, reason: String)
    -> BundleTestStepReport
  {
    let now = Date()
    return BundleTestStepReport(
      index: index,
      id: step.id,
      kind: step.kind,
      actionID: step.actionID,
      status: .skipped,
      startedAt: Self.timestamp(now),
      finishedAt: Self.timestamp(now),
      durationSeconds: 0,
      error: reason)
  }

  private static func timestamp(_ date: Date = Date()) -> String {
    date.formatted(timestampFormat)
  }

  private static let timestampFormat = Date.ISO8601FormatStyle()

  private func stepDescription(_ step: BundleTestStep) -> String {
    switch step.kind {
    case .setup:
      return step.id.map { "setup \($0)" } ?? "setup"
    case .action:
      let identifier = step.actionID ?? step.id ?? "action"
      if let pageID = step.pageID {
        return "action \(identifier) on \(pageID)"
      }
      return "action \(identifier)"
    }
  }

  private func emitStepFinished(
    _ report: BundleTestStepReport,
    totalSteps: Int,
    to progressHandler: (@Sendable (BundleTestProgressEvent) -> Void)?
  ) {
    var message =
      "Step \(report.index)/\(totalSteps) \(report.status.rawValue) in \(Self.duration(report.durationSeconds))"
    if let exitCode = report.exitCode {
      message += " (exit \(exitCode))"
    }
    if report.timedOut {
      message += " (timed out)"
    }
    if let error = report.error {
      message += ": \(error)"
    }
    emit(.message(message), to: progressHandler)
  }

  private static func duration(_ seconds: Double) -> String {
    String(format: "%.1fs", seconds)
  }

  private func emit(
    _ event: BundleTestProgressEvent,
    to progressHandler: (@Sendable (BundleTestProgressEvent) -> Void)?
  ) {
    progressHandler?(event)
  }
}
