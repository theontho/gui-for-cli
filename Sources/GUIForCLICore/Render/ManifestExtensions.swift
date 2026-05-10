import Foundation

public extension CLIBundleManifest {
  var initialFieldValues: [String: String] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
      .filter { $0.kind.persistsFieldValue }
      .reduce(into: [:]) { values, control in
        values[control.id] = control.value ?? values[control.id] ?? ""
      }
  }

  var initialCheckedOptions: [String: Set<String>] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
      .filter { $0.kind == .checkboxGroup }
      .reduce(into: [:]) { values, control in
        values[control.id] = Set(control.options.filter(\.selected).map(\.id))
      }
  }

  var initialConfigValues: [String: String] {
    configEditorControls
      .reduce(into: [:]) { values, control in
        for setting in control.settings {
          values[control.configValueKey(for: setting)] = setting.value ?? ""
        }
      }
  }

  var statefulValueControls: [ControlSpec] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
      .filter { $0.kind.persistsFieldValue }
  }

  var checkboxControls: [ControlSpec] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
      .filter { $0.kind == .checkboxGroup }
  }

}

public extension ControlSpec {
  func configValueKey(for setting: ConfigSettingSpec) -> String {
    "\(id).\(setting.id)"
  }

  var hydratedRows: [ListRowSpec] {
    guard !items.isEmpty else {
      return rows
    }

    let template =
      rowTemplate
      ?? ListRowSpec(
        id: "{{id}}",
        title: "{{name}}",
        values: Dictionary(uniqueKeysWithValues: columns.map { ($0.id, "{{\($0.id)}}") }),
        status: "{{status}}")

    return items.enumerated().map { index, item in
      let fallbackID = item.values["id"].nonEmpty ?? "row-\(index + 1)"
      let id = interpolate(template.id, values: item.values).nonEmpty ?? fallbackID
      let values = template.values.mapValues { interpolate($0, values: item.values) }
      let title = template.title.map { interpolate($0, values: item.values) }.nonEmpty
      let status = template.status.map { interpolate($0, values: item.values) }.nonEmpty
      let tags =
        template.tags.map {
          TagSpec(
            id: interpolate($0.id, values: item.values),
            title: interpolate($0.title, values: item.values),
            style: $0.style)
        }
        .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      let tooltip = template.tooltip.map { interpolate($0, values: item.values) }.nonEmpty

      return ListRowSpec(
        id: id,
        title: title,
        values: values,
        status: status,
        tags: tags,
        tooltip: tooltip)
    }
  }

  private func interpolate(_ value: String, values: [String: String]) -> String {
    var result = value
    let pattern = #"\{\{([^}]+)\}\}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return result
    }
    let matches = regex.matches(
      in: value,
      range: NSRange(value.startIndex..<value.endIndex, in: value))
    for match in matches.reversed() {
      guard
        let placeholderRange = Range(match.range(at: 1), in: value),
        let replacementRange = Range(match.range(at: 0), in: result)
      else {
        continue
      }
      let rawPlaceholder = String(value[placeholderRange]).trimmingCharacters(in: .whitespaces)
      let placeholder =
        rawPlaceholder.hasPrefix("item.") ? String(rawPlaceholder.dropFirst(5)) : rawPlaceholder
      result.replaceSubrange(replacementRange, with: values[placeholder] ?? "")
    }
    return result
  }
}

public extension ControlKind {
  var persistsFieldValue: Bool {
    switch self {
    case .text, .path, .dropdown, .toggle:
      true
    case .checkboxGroup, .infoGrid, .libraryList, .configEditor:
      false
    }
  }
}

public extension Optional where Wrapped == String {
  var nonEmpty: String? {
    guard let value = self else { return nil }
    return value.nonEmpty
  }
}

public extension String {
  var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
