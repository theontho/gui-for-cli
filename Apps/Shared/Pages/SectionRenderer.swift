import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct SectionRenderer: View {
  @EnvironmentObject private var terminal: TerminalLogStore
  @EnvironmentObject private var configStore: BundleConfigStore
  let section: PageSection
  let localizationLabels: BundleLocalizationLabels
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
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
            value: configStore.fieldBinding(for: control),
            checkedIDs: configStore.checkedBinding(for: control),
            bundleRootURL: bundleRootURL,
            runAction: runAction
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
          defaultSystemImage: "rectangle.3.group"
        )
        .axHeading(.h2)
      }
    }
    .axSection(section)
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
      fieldValues: configStore.fieldValues,
      checkedOptions: configStore.checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configStore.configValues.merging(configStore.fieldValues) {
        _, fieldValue in fieldValue
      },
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

  private func commandContext(rowValues: [String: String] = [:]) -> CommandRenderContext {
    CommandRenderContext(
      fieldValues: configStore.fieldValues.merging(sectionValues) { fieldValue, _ in fieldValue },
      checkedOptions: configStore.checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configStore.configValues.merging(configStore.fieldValues) {
        _, fieldValue in fieldValue
      }
      .merging(sectionValues) { configValue, _ in configValue },
      rowValues: rowValues,
      bundleRootPath: bundleRootURL?.path
    )
  }
}
