import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct SectionRenderer: View {
  @EnvironmentObject private var terminal: TerminalLogStore
  let section: PageSection
  let localizationLabels: BundleLocalizationLabels
  @Binding var fieldValues: [String: String]
  @Binding var checkedOptions: [String: Set<String>]
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
  @State private var sectionValues: [String: String] = [:]
  @State private var dataSourceError: String?

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 16) {
        if let subtitle = section.subtitle {
          Text(subtitle)
            .foregroundStyle(.secondary)
            .help(subtitle)
        }

        ForEach(section.controls) { control in
          ControlRenderer(
            control: control,
            localizationLabels: localizationLabels,
            value: binding(for: control),
            checkedIDs: checkedBinding(for: control),
            fieldValues: fieldValues,
            checkedOptions: checkedOptions,
            allFieldValues: $fieldValues,
            configValues: $configValues,
            configFilePaths: $configFilePaths,
            bundleRootURL: bundleRootURL,
            runAction: runAction,
            saveConfig: saveConfig,
            loadConfig: loadConfig,
            persistConfigFilePath: persistConfigFilePath,
            fieldValueChanged: fieldValueChanged,
            checkedOptionsChanged: checkedOptionsChanged,
            configSettingChanged: configSettingChanged
          )
        }

        if !section.actions.isEmpty {
          if hasContentBeforeActions {
            Divider()
          }
          if section.dataSource != nil && sectionValues.isEmpty && dataSourceError == nil {
            HStack(spacing: 8) {
              ProgressView()
                .controlSize(.small)
              Text("Loading...")
                .foregroundStyle(.secondary)
            }
          }
          ActionRow(actions: section.actions, context: commandContext()) { action in
            runAction(action, commandContext())
          }
          .environment(\.bundleLocalizationLabels, localizationLabels)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .bottomLeading) {
        if let dataSourceError {
          Text(dataSourceError)
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.top, 4)
        }
      }
      .task(id: dataSourceTaskID) {
        await loadDataSourceIfNeeded(clearExistingValues: true)
      }
      .onChange(of: terminal.commandCompletionSerial) {
        refreshDataSourceAfterSectionActionIfNeeded()
      }
    } label: {
      if let title = section.title {
        IconTitleLabel(
          title: title,
          iconName: section.iconName,
          iconEmoji: section.iconEmoji,
          defaultSystemImage: "rectangle.3.group")
      }
    }
  }

  private var hasContentBeforeActions: Bool {
    section.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      || !section.controls.isEmpty
  }

  private var dataSourceTaskID: String {
    guard let dataSource = section.dataSource else { return "" }
    return DataSourceRunner.signature(
      dataSource: dataSource,
      rootURL: bundleRootURL,
      context: dataSourceContext())
  }

  private func dataSourceContext() -> CommandRenderContext {
    CommandRenderContext(
      fieldValues: fieldValues,
      checkedOptions: checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configValues.merging(fieldValues) { _, fieldValue in fieldValue },
      bundleRootPath: bundleRootURL?.path
    )
  }

  private func loadDataSourceIfNeeded(clearExistingValues: Bool) async {
    guard let dataSource = section.dataSource, let bundleRootURL else { return }
    if clearExistingValues {
      sectionValues = [:]
    }
    dataSourceError = nil
    do {
      let payload = try await DataSourceRunner.load(
        dataSource: dataSource,
        rootURL: bundleRootURL,
        context: dataSourceContext())
      sectionValues = payload.values ?? [:]
      dataSourceError = nil
    } catch {
      dataSourceError =
        "Could not load \(section.title ?? section.id): \(error.localizedDescription)"
    }
  }

  private func refreshDataSourceAfterSectionActionIfNeeded() {
    guard section.dataSource != nil, let completedCommand = terminal.lastCompletedCommand else {
      return
    }
    let context = commandContext()
    let sectionCommands = section.actions.map { action in
      action.command.displayCommand(resolving: context)
    }
    guard sectionCommands.contains(completedCommand) else { return }
    Task {
      await loadDataSourceIfNeeded(clearExistingValues: false)
    }
  }

  private func binding(for control: ControlSpec) -> Binding<String> {
    Binding(
      get: { fieldValues[control.id, default: control.value ?? ""] },
      set: { fieldValueChanged($0, control) }
    )
  }

  private func checkedBinding(for control: ControlSpec) -> Binding<Set<String>> {
    Binding(
      get: {
        checkedOptions[control.id, default: Set(control.options.filter(\.selected).map(\.id))]
      },
      set: { checkedOptionsChanged($0, control) }
    )
  }

  private func commandContext(rowValues: [String: String] = [:]) -> CommandRenderContext {
    CommandRenderContext(
      fieldValues: fieldValues.merging(sectionValues) { fieldValue, _ in fieldValue },
      checkedOptions: checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configValues.merging(fieldValues) { _, fieldValue in fieldValue }
        .merging(sectionValues) { configValue, _ in configValue },
      rowValues: rowValues,
      bundleRootPath: bundleRootURL?.path
    )
  }
}
