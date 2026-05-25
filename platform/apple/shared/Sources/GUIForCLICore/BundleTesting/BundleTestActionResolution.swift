import Foundation

extension BundleTestRunner {
  func resolveAction(
    step: BundleTestStep,
    manifest: CLIBundleManifest,
    rootURL: URL,
    runtime: BundleTestRuntime
  ) throws -> ResolvedBundleTestAction {
    guard let actionID = step.actionID?.nonEmpty else {
      throw BundleTestError.missingActionID
    }
    let inputs = runtime.inputs.merging(step.inputs)
      .expandingBundlePaths(rootURL: rootURL)
    var matches: [ResolvedBundleTestAction] = []
    for page in manifest.pages where step.pageID == nil || page.id == step.pageID {
      for section in page.sections where step.sectionID == nil || section.id == step.sectionID {
        let sectionContext = context(
          inputs: inputs,
          rowValues: [:],
          rootURL: rootURL,
          placeholderLabels: section.placeholderLabels)
        matches += section.actions
          .filter { $0.id == actionID }
          .map { ResolvedBundleTestAction(action: $0, context: sectionContext) }

        for control in section.controls where step.controlID == nil || control.id == step.controlID
        {
          matches += control.rowActions
            .filter { $0.id == actionID }
            .map {
              ResolvedBundleTestAction(
                action: $0,
                context: context(
                  inputs: inputs,
                  rowValues: rowValues(for: step, control: control, rootURL: rootURL),
                  rootURL: rootURL,
                  placeholderLabels: section.placeholderLabels))
            }
        }
      }
    }

    guard !matches.isEmpty else {
      throw BundleTestError.actionNotFound(actionID)
    }
    guard matches.count == 1 else {
      throw BundleTestError.ambiguousAction(actionID)
    }
    return matches[0]
  }

  private func rowValues(
    for step: BundleTestStep,
    control: ControlSpec,
    rootURL: URL
  ) -> [String: String] {
    let rowID = step.rowID?.nonEmpty
    var values: [String: String] = [:]
    if let rowID {
      if let row = control.hydratedRows.first(where: { $0.id == rowID }) {
        values = row.values
        values["id"] = row.id
        values["title"] = row.title ?? row.id
        if let status = row.status {
          values["status"] = status
        }
      } else {
        values["id"] = rowID
        values["title"] = rowID
      }
    }
    for (key, value) in step.rowValues {
      values[key] = BundlePathResolver.expand(value, rootURL: rootURL)
    }
    return values
  }

  private func context(
    inputs: BundleTestInputs,
    rowValues: [String: String],
    rootURL: URL,
    placeholderLabels: [String: String]
  ) -> CommandRenderContext {
    let checkedOptions = inputs.checkedOptions.mapValues { $0.sorted().joined(separator: ",") }
    return CommandRenderContext(
      fieldValues: inputs.fieldValues,
      checkedOptions: checkedOptions,
      configValues: inputs.configValues.merging(inputs.fieldValues) { _, fieldValue in fieldValue },
      rowValues: rowValues,
      bundleRootPath: rootURL.path,
      placeholderLabels: placeholderLabels)
  }
}

struct BundleTestRuntime {
  var inputs: BundleTestInputs
  var messages: [String]
}

struct ResolvedBundleTestAction {
  var action: ActionSpec
  var context: CommandRenderContext
}

enum BundleTestError: LocalizedError {
  case missingActionID
  case actionNotFound(String)
  case ambiguousAction(String)

  var errorDescription: String? {
    switch self {
    case .missingActionID:
      "Action test steps must specify actionID."
    case .actionNotFound(let actionID):
      "Action not found: \(actionID)"
    case .ambiguousAction(let actionID):
      "Action ID is ambiguous; add pageID, sectionID, or controlID: \(actionID)"
    }
  }
}

extension PageSection {
  var placeholderLabels: [String: String] {
    controls.reduce(into: [:]) { labels, control in
      labels[control.id] = control.label
      for setting in control.settings {
        labels[setting.id] = setting.label
        labels[setting.key] = setting.label
        labels["\(control.id).\(setting.id)"] = setting.label
        labels["\(control.id).\(setting.key)"] = setting.label
      }
    }
  }
}

extension BundleTestInputs {
  func expandingBundlePaths(rootURL: URL) -> BundleTestInputs {
    BundleTestInputs(
      fieldValues: fieldValues.mapValues {
        BundlePathResolver.expand($0, rootURL: rootURL)
      },
      configValues: configValues.mapValues {
        BundlePathResolver.expand($0, rootURL: rootURL)
      },
      checkedOptions: checkedOptions.mapValues {
        $0.map { BundlePathResolver.expand($0, rootURL: rootURL) }
      })
  }
}
