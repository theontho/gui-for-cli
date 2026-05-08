import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct PageRenderer: View {
  let page: BundlePage
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
  var headerAccessory: AnyView?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          IconTitleLabel(
            title: page.title,
            iconName: page.iconName,
            iconEmoji: page.iconEmoji,
            defaultSystemImage: "doc.text"
          )
          .font(.largeTitle.weight(.semibold))
          Text(page.summary)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .help(page.summary)
        }

        if let headerAccessory {
          headerAccessory
        }

        ForEach(page.sections) { section in
          SectionRenderer(
            section: section,
            localizationLabels: localizationLabels,
            fieldValues: $fieldValues,
            checkedOptions: $checkedOptions,
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
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(.background)
  }
}

struct LanguageSettingsSection: View {
  let options: [BundleLocalizationOption]
  let labels: BundleLocalizationLabels
  let selectedCode: String
  let usingSystemDefault: Bool
  var onSelectExplicit: (String) -> Void
  var onSelectSystemDefault: () -> Void

  @State private var isPresenting = false
  @State private var searchText = ""

  private var currentName: String {
    options.first { $0.code == selectedCode }?.displayName ?? selectedCode
  }

  private var buttonLabel: String {
    usingSystemDefault
      ? "\(labels.languageSystemDefaultLabel) — \(currentName)"
      : currentName
  }

  private var filteredOptions: [BundleLocalizationOption] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let sorted = Self.sorted(options)
    if query.isEmpty { return sorted }
    return sorted.filter { option in
      option.displayName.lowercased().contains(query)
        || option.code.lowercased().contains(query)
    }
  }

  private static func sorted(_ options: [BundleLocalizationOption]) -> [BundleLocalizationOption] {
    let englishMatches = options.filter { isEnglish($0.code) }
    let others = options.filter { !isEnglish($0.code) }
      .sorted { lhs, rhs in
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }
    return englishMatches + others
  }

  private static func isEnglish(_ code: String) -> Bool {
    let lower = code.lowercased()
    return lower == "en" || lower.hasPrefix("en-") || lower.hasPrefix("en_")
  }

  var body: some View {
    GroupBox {
      LeadingFormRow {
        Text(labels.languagePickerLabel)
          .font(.headline)
      } content: {
        Button {
          isPresenting.toggle()
        } label: {
          HStack(spacing: 6) {
            Text(buttonLabel)
              .lineLimit(1)
              .truncationMode(.tail)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: 280, alignment: .leading)
        .popover(isPresented: $isPresenting, arrowEdge: .bottom) {
          languageList
        }
      }
    } label: {
      Label(labels.languageSectionTitle, systemImage: "globe")
    }
  }

  private var languageList: some View {
    VStack(alignment: .leading, spacing: 0) {
      TextField(labels.languageSearchPlaceholder, text: $searchText)
        .textFieldStyle(.roundedBorder)
        .padding(8)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          languageRow(
            title: labels.languageSystemDefaultLabel,
            subtitle: nil,
            isSelected: usingSystemDefault,
            action: {
              isPresenting = false
              onSelectSystemDefault()
            })
          Divider()
          ForEach(filteredOptions) { option in
            languageRow(
              title: option.displayName,
              subtitle: option.code,
              isSelected: !usingSystemDefault && option.code == selectedCode,
              action: {
                isPresenting = false
                onSelectExplicit(option.code)
              })
          }
        }
      }
      .frame(minWidth: 280, maxHeight: 360)
    }
    .frame(minWidth: 280)
  }

  @ViewBuilder
  private func languageRow(
    title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: isSelected ? "checkmark" : "circle")
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
          .frame(width: 16)
        VStack(alignment: .leading, spacing: 1) {
          Text(title)
          if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

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
