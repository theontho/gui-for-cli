import Foundation
import GUIForCLICore

@MainActor
enum DataSourceRenderContext {
  static func base(
    configStore: BundleConfigStore,
    bundleRootURL: URL?,
    placeholderLabels: [String: String] = [:]
  ) -> CommandRenderContext {
    CommandRenderContext(
      fieldValues: configStore.fieldValues,
      checkedOptions: checkedOptions(configStore),
      configValues: configStore.configValues.merging(configStore.fieldValues) {
        _, fieldValue in fieldValue
      },
      bundleRootPath: bundleRootURL?.path,
      placeholderLabels: placeholderLabels)
  }

  static func section(
    configStore: BundleConfigStore,
    sectionValues: [String: String],
    rowValues: [String: String] = [:],
    bundleRootURL: URL?,
    placeholderLabels: [String: String]
  ) -> CommandRenderContext {
    CommandRenderContext(
      fieldValues: configStore.fieldValues.merging(sectionValues) { fieldValue, _ in fieldValue },
      checkedOptions: checkedOptions(configStore),
      configValues: configStore.configValues.merging(configStore.fieldValues) {
        _, fieldValue in fieldValue
      }
      .merging(sectionValues) { configValue, _ in configValue },
      rowValues: rowValues,
      bundleRootPath: bundleRootURL?.path,
      placeholderLabels: placeholderLabels)
  }

  static func row(
    _ row: ListRowSpec,
    configStore: BundleConfigStore,
    bundleRootURL: URL?
  ) -> CommandRenderContext {
    var rowValues = row.values
    rowValues["id"] = row.id
    rowValues["title"] = row.title ?? row.id
    if let status = row.status {
      rowValues["status"] = status
    }
    return CommandRenderContext(
      fieldValues: configStore.fieldValues,
      checkedOptions: checkedOptions(configStore),
      configValues: configStore.configValues,
      rowValues: rowValues,
      bundleRootPath: bundleRootURL?.path)
  }

  private static func checkedOptions(_ configStore: BundleConfigStore) -> [String: String] {
    configStore.checkedOptions.mapValues { $0.sorted().joined(separator: ",") }
  }
}

enum DataSourceRefreshMatcher {
  static func completedCommand(_ completedCommand: String?, matches commands: [String]) -> Bool {
    guard let completedCommand else {
      return false
    }
    return commands.contains(completedCommand)
  }
}
