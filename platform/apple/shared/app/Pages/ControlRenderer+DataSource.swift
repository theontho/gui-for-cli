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
    DataSourceRenderContext.base(configStore: configStore, bundleRootURL: bundleRootURL)
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
    guard control.dataSource != nil else {
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
    guard
      DataSourceRefreshMatcher.completedCommand(
        terminal.lastCompletedCommand,
        matches: controlCommands)
    else { return }

    Task {
      await loadDataSourceIfNeeded(clearExistingData: false)
    }
  }

  private func commandContext(for row: ListRowSpec) -> CommandRenderContext {
    DataSourceRenderContext.row(row, configStore: configStore, bundleRootURL: bundleRootURL)
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
