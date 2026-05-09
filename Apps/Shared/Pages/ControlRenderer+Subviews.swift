import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

extension ControlRenderer {
  @ViewBuilder
  func subview(for renderedControl: ControlSpec) -> some View {
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
      checkboxGroupView(renderedControl)
    case .infoGrid:
      infoGridView(renderedControl)
    case .libraryList:
      libraryListView(renderedControl)
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

  @ViewBuilder
  private func checkboxGroupView(_ renderedControl: ControlSpec) -> some View {
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
  }

  private func infoGridView(_ renderedControl: ControlSpec) -> some View {
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
  }

  @ViewBuilder
  private func libraryListView(_ renderedControl: ControlSpec) -> some View {
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
  }

  func label(for control: ControlSpec) -> some View {
    InfoLabel(text: control.label, tooltip: control.tooltip, font: .headline)
  }

  func labeledControl<Content: View>(
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

  func checkbox(for option: ControlOption) -> some View {
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

  func displayTitle(for option: ControlOption) -> String {
    guard let status = option.status, !status.isEmpty else { return option.title }
    let localized =
      localizationLabels.libraryStatusLabels[status.lowercased()] ?? status
    return "\(option.title) (\(localized))"
  }
}
