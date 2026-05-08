import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct ControlRenderer: View {
  @EnvironmentObject private var terminal: TerminalLogStore
  let control: ControlSpec
  let localizationLabels: BundleLocalizationLabels
  @Binding var value: String
  @Binding var checkedIDs: Set<String>
  let fieldValues: [String: String]
  let checkedOptions: [String: Set<String>]
  @Binding var allFieldValues: [String: String]
  @Binding var configValues: [String: String]
  @Binding var configFilePaths: [String: String]
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
  var saveConfig: (ControlSpec) -> Void
  var loadConfig: (ControlSpec) -> Void
  var persistConfigFilePath: (String, ControlSpec) -> Void
  var fieldValueChanged: (String, ControlSpec) -> Void
  var checkedOptionsChanged: (Set<String>, ControlSpec) -> Void
  var configSettingChanged: (String, ConfigSettingSpec, ControlSpec) -> Void
  @State private var dynamicData = DynamicControlData()
  @State private var dataSourceError: String?
  @State private var isRefreshingDataSource = false

  var body: some View {
    let renderedControl = control.applying(dynamicData)
    Group {
      switch renderedControl.kind {
      case .text:
        labeledControl(renderedControl) {
          TextField(renderedControl.placeholder ?? "", text: $value)
        }
      case .path:
        labeledControl(renderedControl) {
          HStack {
            TextField(renderedControl.placeholder ?? "", text: $value)
            PathPickerButton(
              path: $value,
              labels: localizationLabels,
              rootURL: bundleRootURL)
          }
        }
      case .dropdown:
        labeledControl(renderedControl) {
          Picker("", selection: $value) {
            ForEach(renderedControl.options) { option in
              Text(displayTitle(for: option)).tag(option.id)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      case .toggle:
        labeledControl(renderedControl) {
          Toggle(
            "", isOn: Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" })
          )
          .labelsHidden()
        }
      case .checkboxGroup:
        if renderedControl.options.count == 1, let option = renderedControl.options.first {
          labeledControl(renderedControl) {
            checkbox(for: option)
          }
        } else {
          VStack(alignment: .leading, spacing: 10) {
            label(for: renderedControl)
            LazyVGrid(
              columns: [GridItem(.adaptive(minimum: 240), alignment: .leading)], spacing: 8
            ) {
              ForEach(renderedControl.options) { option in
                checkbox(for: option)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .help(renderedControl.tooltip ?? "")
        }
      case .infoGrid:
        VStack(alignment: .leading, spacing: 10) {
          label(for: renderedControl)
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 280), alignment: .leading)], spacing: 8
          ) {
            ForEach(renderedControl.options) { option in
              Text(displayTitle(for: option))
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
        }
        .help(renderedControl.tooltip ?? "")
      case .libraryList:
        if control.dataSource != nil && dynamicData.rows == nil {
          LibraryListLoadingControl(
            control: control,
            localizationLabels: localizationLabels,
            isLoading: dataSourceError == nil,
            errorMessage: dataSourceError
          ) {
            Task {
              await loadDataSourceIfNeeded(clearExistingData: true)
            }
          }
        } else {
          LibraryListControl(
            control: renderedControl,
            localizationLabels: localizationLabels,
            fieldValues: fieldValues,
            checkedOptions: checkedOptions,
            configValues: configValues,
            bundleRootURL: bundleRootURL,
            isRefreshing: isRefreshingDataSource,
            dataSourceError: dataSourceError,
            retryDataSource: {
              Task {
                await loadDataSourceIfNeeded(clearExistingData: true)
              }
            },
            runAction: runAction
          )
        }
      case .configEditor:
        ConfigEditorControl(
          control: renderedControl,
          localizationLabels: localizationLabels,
          fieldValues: $allFieldValues,
          configValues: $configValues,
          configFilePaths: $configFilePaths,
          bundleRootURL: bundleRootURL,
          loadConfig: loadConfig,
          persistConfigFilePath: persistConfigFilePath,
          configSettingChanged: configSettingChanged
        )
      }
    }
    .overlay(alignment: .bottomLeading) {
      if let dataSourceError, renderedControl.kind != .libraryList {
        Text(dataSourceError)
          .font(.caption)
          .foregroundStyle(.orange)
          .padding(.top, 4)
      }
    }
    .task(id: dataSourceTaskID) {
      await loadDataSourceIfNeeded(clearExistingData: true)
    }
    .onChange(of: terminal.commandCompletionSerial) {
      refreshDataSourceAfterControlActionIfNeeded()
    }
  }

  private func label(for control: ControlSpec) -> some View {
    InfoLabel(text: control.label, tooltip: control.tooltip, font: .headline)
  }

  private func labeledControl<Content: View>(
    _ control: ControlSpec,
    @ViewBuilder content: () -> Content
  ) -> some View {
    LeadingFormRow {
      label(for: control)
    } content: {
      content()
    }
    .help(control.tooltip ?? "")
  }

  private var dataSourceTaskID: String {
    guard let dataSource = control.dataSource else { return "" }
    return DataSourceRunner.signature(
      dataSource: dataSource,
      rootURL: bundleRootURL,
      context: dataSourceContext)
  }

  private var dataSourceContext: CommandRenderContext {
    CommandRenderContext(
      fieldValues: allFieldValues,
      checkedOptions: checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configValues.merging(allFieldValues) { _, fieldValue in fieldValue },
      bundleRootPath: bundleRootURL?.path)
  }

  private func loadDataSourceIfNeeded(clearExistingData: Bool) async {
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

  private func refreshDataSourceAfterControlActionIfNeeded() {
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

  private func selectDefaultOptionIfNeeded(_ options: [ControlOption]?) {
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

  private func checkbox(for option: ControlOption) -> some View {
    let toggle = Toggle(
      displayTitle(for: option),
      isOn: Binding(
        get: { checkedIDs.contains(option.id) },
        set: { isSelected in
          if isSelected {
            checkedIDs.insert(option.id)
          } else {
            checkedIDs.remove(option.id)
          }
        }
      )
    )
    .frame(maxWidth: .infinity, alignment: .leading)
    #if os(macOS)
      return toggle.toggleStyle(.checkbox)
    #else
      return toggle
    #endif
  }

  private func displayTitle(for option: ControlOption) -> String {
    guard let status = option.status, !status.isEmpty else { return option.title }
    let localized =
      localizationLabels.libraryStatusLabels[status.lowercased()] ?? status
    return "\(option.title) (\(localized))"
  }
}
