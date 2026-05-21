import GUIForCLICore
import SwiftUI

struct LibraryListControl: View {
  @EnvironmentObject private var configStore: BundleConfigStore
  let control: ControlSpec
  let localizationLabels: BundleLocalizationLabels
  let bundleRootURL: URL?
  var isRefreshing = false
  var dataSourceError: String?
  var retryDataSource: () -> Void = {}
  var runAction: (ActionSpec, CommandRenderContext) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        InfoLabel(text: control.label, tooltip: control.tooltip, font: .headline)
        if isRefreshing {
          ProgressView()
            .controlSize(.small)
          Text(localizationLabels.refreshingTitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      let rows = control.hydratedRows
      if rows.isEmpty {
        Text(emptyMessage)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
          .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      } else {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
          GridRow {
            ForEach(control.columns) { column in
              Text(column.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            if !control.rowActions.isEmpty {
              Text(localizationLabels.actionsColumnTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
          }

          Divider()
            .gridCellColumns(control.columns.count + (control.rowActions.isEmpty ? 0 : 1))

          ForEach(rows) { row in
            GridRow {
              ForEach(control.columns) { column in
                rowCell(row: row, column: column)
              }

              if !control.rowActions.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                  let context = commandContext(for: row)
                  ForEach(visibleRowActions(for: row, context: context)) { action in
                    ActionButton(action: action) {
                      runAction(action, context)
                    }
                    .environment(\.commandRenderContext, context)
                  }
                }
              }
            }
          }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      }

      if let dataSourceError {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(.orange)
          Text(dataSourceError)
            .font(.caption)
            .foregroundStyle(.secondary)
          Button(localizationLabels.retryButtonTitle, action: retryDataSource)
            .buttonStyle(.borderless)
            .font(.caption)
        }
      }
    }
    .help(control.tooltip ?? "")
  }

  private var emptyMessage: String {
    if control.dataSource != nil {
      return "No library items were found for the selected reference library."
    }
    return "No library items are defined."
  }

  @ViewBuilder
  private func rowCell(row: ListRowSpec, column: ListColumnSpec) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      if column.id == "build", let buildStyle = buildTagStyle(for: row) {
        TagPill(
          tag: TagSpec(
            id: "build",
            title: displayValue(for: column, row: row),
            style: buildStyle),
          uppercased: false)
      } else {
        Text(displayValue(for: column, row: row))
          .font(column.id == "name" ? .body.weight(.medium) : .body)
      }
      if column.id == "name", row.status != nil || !row.tags.isEmpty {
        HStack(spacing: 4) {
          if let status = row.status {
            TagPill(
              tag: TagSpec(
                id: "status",
                title: localizedStatus(status),
                style: tagStyle(for: status)))
          }
          ForEach(row.tags) { tag in
            TagPill(tag: localizedTag(tag))
          }
        }
      }
    }
    .help(row.tooltip ?? "")
  }

  private func displayValue(for column: ListColumnSpec, row: ListRowSpec) -> String {
    if column.id == "name" {
      return row.title ?? row.values[column.id] ?? row.id
    }
    if column.id == "status" {
      if let status = row.status {
        return localizedStatus(status)
      }
      return row.values[column.id] ?? ""
    }
    return row.values[column.id] ?? ""
  }

  private func localizedStatus(_ status: String) -> String {
    localizationLabels.libraryStatusLabels[status.lowercased()] ?? status
  }

  private func localizedTag(_ tag: TagSpec) -> TagSpec {
    var tag = tag
    tag.title =
      localizationLabels.libraryTagLabels[tag.id]
      ?? localizationLabels.libraryTagLabels[tag.title.lowercased()]
      ?? tag.title
    return tag
  }

  private func commandContext(for row: ListRowSpec) -> CommandRenderContext {
    var rowValues = row.values
    rowValues["id"] = row.id
    rowValues["title"] = row.title ?? row.id
    if let status = row.status {
      rowValues["status"] = status
    }
    return CommandRenderContext(
      fieldValues: configStore.fieldValues,
      checkedOptions: configStore.checkedOptions.mapValues { $0.sorted().joined(separator: ",") },
      configValues: configStore.configValues,
      rowValues: rowValues,
      bundleRootPath: bundleRootURL?.path
    )
  }

  private func visibleRowActions(for row: ListRowSpec, context: CommandRenderContext)
    -> [ActionSpec]
  {
    control.rowActions.filter { $0.isVisible(resolving: context) }
  }

  private func tagStyle(for status: String) -> TagStyle {
    switch status.lowercased() {
    case "installed":
      return .success
    case "unindexed", "incomplete":
      return .warning
    case "missing":
      return .secondary
    default:
      return .primary
    }
  }

  private func buildTagStyle(for row: ListRowSpec) -> TagStyle? {
    let value = row.values["build"] ?? ""
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    let lower = trimmed.lowercased()
    if lower.contains("grch37") || lower.contains("hg19") {
      return .primary
    }
    if lower.contains("grch38") || lower.contains("hg38") {
      return .success
    }
    if lower.contains("t2t") || lower.contains("chm13") {
      return .warning
    }
    return .secondary
  }
}
