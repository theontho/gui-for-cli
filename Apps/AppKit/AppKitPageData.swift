import AppKit
import GUIForCLICore

extension AppKitPageViewController {
  func refreshDynamicDataAfterCommand() {
    guard page.sections.contains(where: sectionHasDataSource) else { return }
    dynamicLoadGeneration &+= 1
    dynamicControls = [:]
    dynamicErrors = [:]
    loadingIDs.removeAll()
    sectionValues = [:]
    renderPage()
  }

  func loadControlDataIfNeeded(_ control: ControlSpec, in section: PageSection) {
    guard let dataSource = control.dataSource,
      dynamicControls[control.id] == nil,
      !loadingIDs.contains(control.id)
    else { return }
    loadingIDs.insert(control.id)
    let generation = dynamicLoadGeneration
    let context = commandContext(for: section)
    Task {
      do {
        let payload = try await DataSourceRunner.load(
          dataSource: dataSource,
          rootURL: state.bundleRootURL,
          context: context)
        guard generation == dynamicLoadGeneration else { return }
        dynamicControls[control.id] = DynamicControlData(payload: payload)
        dynamicErrors[control.id] = nil
      } catch {
        guard generation == dynamicLoadGeneration else { return }
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
    let generation = dynamicLoadGeneration
    let context = commandContext(for: section)
    Task {
      do {
        let payload = try await DataSourceRunner.load(
          dataSource: dataSource,
          rootURL: state.bundleRootURL,
          context: context)
        guard generation == dynamicLoadGeneration else { return }
        sectionValues[section.id] = payload.values ?? [:]
        dynamicErrors[section.id] = nil
      } catch {
        guard generation == dynamicLoadGeneration else { return }
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

  func libraryCommandContext(for row: ListRowSpec, in section: PageSection) -> CommandRenderContext
  {
    var rowValues = row.values
    rowValues["id"] = row.id
    rowValues["title"] = row.title ?? row.id
    if let status = row.status {
      rowValues["status"] = status
    }
    return commandContext(for: section, rowValues: rowValues)
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
