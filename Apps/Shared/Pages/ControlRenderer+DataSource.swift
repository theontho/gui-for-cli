import GUIForCLICore
import SwiftUI

extension ControlRenderer {
  var dataSourceTaskID: String {
    guard let dataSource = control.dataSource else { return "" }
    return DataSourceRunner.signature(
      dataSource: dataSource,
      rootURL: bundleRootURL,
      context: dataSourceContext)
  }

  var dataSourceContext: CommandRenderContext {
    CommandRenderContext(
      fieldValues: allFieldValues,
      checkedOptions: checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configValues.merging(allFieldValues) { _, fieldValue in fieldValue },
      bundleRootPath: bundleRootURL?.path)
  }

  func loadDataSourceIfNeeded(clearExistingData: Bool) async {
    guard let dataSource = control.dataSource, let bundleRootURL else { return }
    if clearExistingData {
      dynamicData = DynamicControlData()
    } else {
      isRefreshingDataSource = true
    }
    dataSourceError = nil
    defer {
      isRefreshingDataSource = false
    }
    do {
      let payload = try await DataSourceRunner.load(
        dataSource: dataSource,
        rootURL: bundleRootURL,
        context: dataSourceContext)
      dynamicData = DynamicControlData(payload: payload)
      selectDefaultOptionIfNeeded(payload.options)
      dataSourceError = nil
    } catch {
      dataSourceError = "Could not load \(control.label): \(error.localizedDescription)"
    }
  }

  func refreshDataSourceAfterControlActionIfNeeded() {
    guard control.dataSource != nil, let completedCommand = terminal.lastCompletedCommand else {
      return
    }
    let renderedControl = control.applying(dynamicData)
    guard renderedControl.kind == .libraryList else { return }

    let controlCommands = renderedControl.hydratedRows.flatMap { row in
      let context = commandContext(for: row)
      return renderedControl.rowActions
        .filter { $0.isVisible(resolving: context) }
        .map { $0.command.displayCommand(resolving: context) }
    }
    guard controlCommands.contains(completedCommand) else { return }

    Task {
      await loadDataSourceIfNeeded(clearExistingData: false)
    }
  }

  private func commandContext(for row: ListRowSpec) -> CommandRenderContext {
    var rowValues = row.values
    rowValues["id"] = row.id
    rowValues["title"] = row.title ?? row.id
    if let status = row.status {
      rowValues["status"] = status
    }
    return CommandRenderContext(
      fieldValues: fieldValues,
      checkedOptions: checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configValues,
      rowValues: rowValues,
      bundleRootPath: bundleRootURL?.path
    )
  }

  func selectDefaultOptionIfNeeded(_ options: [ControlOption]?) {
    guard let options else {
      return
    }
    let currentValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !currentValue.isEmpty, options.contains(where: { $0.id == currentValue }) {
      return
    }
    if let defaultOption = options.first(where: \.selected) ?? options.first {
      value = defaultOption.id
    } else if !currentValue.isEmpty {
      value = ""
    }
  }
}
