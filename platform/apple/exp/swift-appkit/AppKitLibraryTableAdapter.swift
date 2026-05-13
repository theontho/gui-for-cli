import AppKit
import GUIForCLICore

@MainActor
final class AppKitLibraryTableAdapter: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  static let actionsColumnID = "actions"

  private let control: ControlSpec
  private let labels: BundleLocalizationLabels
  private let rows: [ListRowSpec]
  private let section: PageSection
  private let bodyFontSize: CGFloat
  private weak var pageController: AppKitPageViewController?

  init(
    control: ControlSpec,
    labels: BundleLocalizationLabels,
    rows: [ListRowSpec],
    section: PageSection,
    bodyFontSize: CGFloat,
    pageController: AppKitPageViewController
  ) {
    self.control = control
    self.labels = labels
    self.rows = rows
    self.section = section
    self.bodyFontSize = bodyFontSize
    self.pageController = pageController
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    rows.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
    -> NSView?
  {
    guard row < rows.count, let tableColumn else { return nil }
    let rowSpec = rows[row]
    let columnID = tableColumn.identifier.rawValue
    let cell = NSTableCellView()
    cell.identifier = tableColumn.identifier

    let content =
      columnID == Self.actionsColumnID
      ? actionsCell(for: rowSpec)
      : valueCell(for: rowSpec, columnID: columnID)

    cell.addSubview(content)
    content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
      content.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
      content.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      content.topAnchor.constraint(greaterThanOrEqualTo: cell.topAnchor, constant: 4),
      content.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor, constant: -4),
    ])
    return cell
  }

  private func valueCell(for row: ListRowSpec, columnID: String) -> NSView {
    if columnID == "name" {
      let stack = AppKitViewFactory.verticalStack(spacing: 2)
      stack.alignment = .leading

      let title = NSTextField(labelWithString: displayValue(for: row, columnID: columnID))
      title.font = .systemFont(ofSize: bodyFontSize, weight: .medium)
      title.lineBreakMode = .byTruncatingTail
      title.maximumNumberOfLines = 1
      stack.addArrangedSubview(title)

      if let metadata = metadataText(for: row) {
        let metadataLabel = AppKitViewFactory.secondaryLabel(metadata, size: bodyFontSize - 2)
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1
        stack.addArrangedSubview(metadataLabel)
      }

      stack.toolTip = row.tooltip
      return stack
    }

    let label = AppKitViewFactory.secondaryLabel(displayValue(for: row, columnID: columnID))
    label.font = .systemFont(ofSize: bodyFontSize)
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 2
    label.toolTip = row.tooltip
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
  }

  private func actionsCell(for row: ListRowSpec) -> NSView {
    guard let pageController else { return NSView() }
    let context = pageController.libraryCommandContext(for: row, in: section)
    let actions = control.rowActions.filter { $0.isVisible(resolving: context) }
    guard !actions.isEmpty else { return NSView() }
    let actionRow = pageController.actionRow(actions, context: context) { [weak pageController] in
      pageController?.libraryCommandContext(for: row, in: self.section) ?? context
    }
    actionRow.setAccessibilityLabel("\(labels.actionsColumnTitle): \(row.title ?? row.id)")
    return actionRow
  }

  private func displayValue(for row: ListRowSpec, columnID: String) -> String {
    if columnID == "name" {
      return row.title ?? row.values[columnID] ?? row.id
    }
    if columnID == "status", let status = row.status {
      return localizedStatus(status)
    }
    return row.values[columnID] ?? ""
  }

  private func metadataText(for row: ListRowSpec) -> String? {
    var metadata: [String] = []
    if let status = row.status {
      metadata.append(localizedStatus(status))
    }
    metadata.append(contentsOf: row.tags.map(localizedTagTitle))
    return metadata.isEmpty ? nil : metadata.joined(separator: " / ")
  }

  private func localizedStatus(_ status: String) -> String {
    labels.libraryStatusLabels[status.lowercased()] ?? status
  }

  private func localizedTagTitle(_ tag: TagSpec) -> String {
    labels.libraryTagLabels[tag.id]
      ?? labels.libraryTagLabels[tag.title.lowercased()]
      ?? tag.title
  }
}
