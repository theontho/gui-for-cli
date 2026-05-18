import GUIForCLICore
import SwiftUI

struct ConfigSettingRenderer: View {
  let setting: ConfigSettingSpec
  @Binding var value: String
  let localizationLabels: BundleLocalizationLabels
  let bundleRootURL: URL?
  let context: CommandRenderContext
  @State private var dynamicOptions: [ControlOption]?
  @State private var dataSourceError: String?

  var body: some View {
    let renderedOptions = dynamicOptions ?? setting.options
    LeadingFormRow {
      InfoLabel(text: setting.label, tooltip: setting.tooltip)
    } content: {
      switch setting.kind {
      case .dropdown:
        Picker("", selection: $value) {
          ForEach(renderedOptions) { option in
            Text(displayTitle(for: option)).tag(option.id)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
      case .toggle:
        Toggle("", isOn: Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" }))
          .labelsHidden()
      default:
        HStack {
          TextField(setting.placeholder ?? "", text: $value)
          if setting.kind == .path {
            PathPickerButton(
              path: $value,
              labels: localizationLabels,
              rootURL: bundleRootURL,
              defaultDirectoryPath: setting.defaultDirectory.map { context.interpolated($0) })
          }
        }
      }
    }
    .help(setting.tooltip ?? "")
    .overlay(alignment: .bottomLeading) {
      if let dataSourceError {
        Text(dataSourceError)
          .font(.caption)
          .foregroundStyle(.orange)
          .padding(.top, 4)
      }
    }
    .task(id: dataSourceTaskID) {
      await loadDataSourceIfNeeded()
    }
  }

  private var dataSourceTaskID: String {
    guard let dataSource = setting.dataSource else { return "" }
    return DataSourceRunner.signature(
      dataSource: dataSource,
      rootURL: bundleRootURL,
      context: context)
  }

  private func loadDataSourceIfNeeded() async {
    guard let dataSource = setting.dataSource, let bundleRootURL else { return }
    do {
      let payload = try await DataSourceRunner.load(
        dataSource: dataSource,
        rootURL: bundleRootURL,
        context: context)
      dynamicOptions = payload.options
      selectDefaultOptionIfNeeded(payload.options)
      dataSourceError = nil
    } catch {
      dataSourceError = "Could not load \(setting.label): \(error.localizedDescription)"
    }
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

  private func displayTitle(for option: ControlOption) -> String {
    guard let status = option.status, !status.isEmpty else { return option.title }
    let localized =
      localizationLabels.libraryStatusLabels[status.lowercased()] ?? status
    return "\(option.title) (\(localized))"
  }
}
