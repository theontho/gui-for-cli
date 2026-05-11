import AppKit
import GUIForCLICore

extension AppKitPageViewController {
  func refreshDynamicDataAfterCommand() {
    guard page.sections.contains(where: sectionHasDataSource) else { return }
    dynamicControls = [:]
    sectionValues = [:]
    renderPage()
  }

  func loadControlDataIfNeeded(_ control: ControlSpec, in section: PageSection) {
    guard let dataSource = control.dataSource,
      dynamicControls[control.id] == nil,
      !loadingIDs.contains(control.id)
    else { return }
    loadingIDs.insert(control.id)
    let context = commandContext(for: section)
    Task {
      do {
        let payload = try await DataSourceRunner.load(
          dataSource: dataSource,
          rootURL: state.bundleRootURL,
          context: context)
        dynamicControls[control.id] = DynamicControlData(payload: payload)
        dynamicErrors[control.id] = nil
      } catch {
        dynamicErrors[control.id] = "Could not load \(control.label): \(error.localizedDescription)"
      }
      loadingIDs.remove(control.id)
      renderPage()
    }
  }

  func loadSectionDataIfNeeded(_ section: PageSection) {
    guard let dataSource = section.dataSource,
      sectionValues[section.id] == nil,
      !loadingIDs.contains(section.id)
    else { return }
    loadingIDs.insert(section.id)
    Task {
      do {
        let payload = try await DataSourceRunner.load(
          dataSource: dataSource,
          rootURL: state.bundleRootURL,
          context: commandContext(for: section))
        sectionValues[section.id] = payload.values ?? [:]
        dynamicErrors[section.id] = nil
      } catch {
        dynamicErrors[section.id] =
          "Could not load \(section.title ?? section.id): \(error.localizedDescription)"
      }
      loadingIDs.remove(section.id)
      renderPage()
    }
  }

  func commandContext(for section: PageSection? = nil, rowValues: [String: String] = [:])
    -> CommandRenderContext
  {
    let extraValues = section.flatMap { sectionValues[$0.id] } ?? [:]
    return CommandRenderContext(
      fieldValues: state.fieldValues.merging(extraValues) { fieldValue, _ in fieldValue },
      checkedOptions: state.checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: state.configValues.merging(state.fieldValues) { _, fieldValue in fieldValue }
        .merging(extraValues) { configValue, _ in configValue },
      rowValues: rowValues,
      bundleRootPath: state.bundleRootURL.path,
      placeholderLabels: section?.placeholderLabels ?? [:])
  }

  func libraryCommandContext(for row: ListRowSpec) -> CommandRenderContext {
    var rowValues = row.values
    rowValues["id"] = row.id
    rowValues["title"] = row.title ?? row.id
    if let status = row.status {
      rowValues["status"] = status
    }
    return commandContext(rowValues: rowValues)
  }

  func displayTitle(for option: ControlOption) -> String {
    guard let status = option.status, !status.isEmpty else { return option.title }
    let localized = labels.libraryStatusLabels[status.lowercased()] ?? status
    return "\(option.title) (\(localized))"
  }

  private func sectionHasDataSource(_ section: PageSection) -> Bool {
    section.dataSource != nil || section.controls.contains { $0.dataSource != nil }
  }
}

final class AppKitActionInvocation: NSObject {
  let action: ActionSpec
  let context: CommandRenderContext

  init(action: ActionSpec, context: CommandRenderContext) {
    self.action = action
    self.context = context
  }
}

final class AppKitActionButton: NSButton {
  var invocation: AppKitActionInvocation?
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
