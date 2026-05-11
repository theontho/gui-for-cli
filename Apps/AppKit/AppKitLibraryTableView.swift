import AppKit
import GUIForCLICore

@MainActor
final class AppKitLibraryTableView: NSView {
  private let scrollView = NSScrollView()
  private let tableView = NSTableView()
  private let control: ControlSpec
  private let rows: [ListRowSpec]
  private var adapter: AppKitLibraryTableAdapter?

  init(
    control: ControlSpec,
    labels: BundleLocalizationLabels,
    rows: [ListRowSpec],
    bodyFontSize: CGFloat,
    pageController: AppKitPageViewController
  ) {
    self.control = control
    self.rows = rows
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    let adapter = AppKitLibraryTableAdapter(
      control: control,
      labels: labels,
      rows: rows,
      bodyFontSize: bodyFontSize,
      pageController: pageController)
    self.adapter = adapter

    configureTable(control: control, labels: labels, rows: rows, adapter: adapter)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  private func configureTable(
    control: ControlSpec,
    labels: BundleLocalizationLabels,
    rows: [ListRowSpec],
    adapter: AppKitLibraryTableAdapter
  ) {
    scrollView.hasVerticalScroller = rows.count > 8
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.borderType = .bezelBorder
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    tableView.usesAlternatingRowBackgroundColors = true
    tableView.rowHeight = 48
    tableView.intercellSpacing = NSSize(width: 8, height: 4)
    tableView.columnAutoresizingStyle = .noColumnAutoresizing
    tableView.allowsColumnResizing = true
    tableView.allowsColumnReordering = false
    tableView.allowsMultipleSelection = false
    tableView.dataSource = adapter
    tableView.delegate = adapter
    tableView.setAccessibilityLabel(control.label)

    for column in control.columns {
      let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
      tableColumn.title = column.title
      tableColumn.minWidth = minimumWidth(for: column.id)
      tableColumn.width = preferredWidth(for: column.id)
      tableView.addTableColumn(tableColumn)
    }

    if !control.rowActions.isEmpty {
      let tableColumn = NSTableColumn(
        identifier: NSUserInterfaceItemIdentifier(AppKitLibraryTableAdapter.actionsColumnID))
      tableColumn.title = labels.actionsColumnTitle
      tableColumn.minWidth = 150
      tableColumn.width = 220
      tableView.addTableColumn(tableColumn)
    }

    scrollView.documentView = tableView
    addSubview(scrollView)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
      heightAnchor.constraint(equalToConstant: tableHeight(for: rows.count)),
    ])
  }

  override func layout() {
    super.layout()
    guard scrollView.contentView.bounds.width > 0 else { return }
    layoutTableToFillScrollView()
  }

  private func layoutTableToFillScrollView() {
    let availableWidth = max(scrollView.contentView.bounds.width, minimumTableWidth)
    let availableHeight = max(
      scrollView.contentView.bounds.height,
      tableHeaderHeight + CGFloat(rows.count)
        * (tableView.rowHeight + tableView.intercellSpacing.height))
    tableView.frame = NSRect(x: 0, y: 0, width: availableWidth, height: availableHeight)
    resizeColumns(to: availableWidth)
  }

  private func resizeColumns(to availableWidth: CGFloat) {
    let spacing =
      CGFloat(max(tableView.tableColumns.count - 1, 0)) * tableView.intercellSpacing.width
    let actionsWidth: CGFloat = control.rowActions.isEmpty ? 0 : 220
    let dataWidth = max(
      minimumDataColumnsWidth,
      availableWidth - spacing - actionsWidth)
    let nonNameColumns = control.columns.filter { $0.id != "name" }
    let nameWidth = max(minimumWidth(for: "name"), dataWidth * 0.34)
    let remainingDataWidth = max(0, dataWidth - nameWidth)
    let otherWidth =
      nonNameColumns.isEmpty
      ? 0
      : max(110, remainingDataWidth / CGFloat(nonNameColumns.count))

    for tableColumn in tableView.tableColumns {
      let id = tableColumn.identifier.rawValue
      if id == AppKitLibraryTableAdapter.actionsColumnID {
        tableColumn.width = actionsWidth
      } else if id == "name" {
        tableColumn.width = nameWidth
      } else {
        tableColumn.width = otherWidth
      }
    }
  }

  private var tableHeaderHeight: CGFloat {
    tableView.headerView?.frame.height ?? 24
  }

  private var minimumTableWidth: CGFloat {
    minimumDataColumnsWidth + (control.rowActions.isEmpty ? 0 : 220)
      + CGFloat(max(tableView.tableColumns.count - 1, 0)) * tableView.intercellSpacing.width
  }

  private var minimumDataColumnsWidth: CGFloat {
    control.columns.reduce(CGFloat(0)) { total, column in
      total + minimumWidth(for: column.id)
    }
  }

  private func tableHeight(for rowCount: Int) -> CGFloat {
    min(max(72 + CGFloat(rowCount) * 52, 132), 440)
  }

  private func minimumWidth(for columnID: String) -> CGFloat {
    columnID == "name" ? 220 : 110
  }

  private func preferredWidth(for columnID: String) -> CGFloat {
    columnID == "name" ? 320 : 150
  }
}

@MainActor
private final class AppKitLibraryTableAdapter: NSObject, NSTableViewDataSource, NSTableViewDelegate
{
  static let actionsColumnID = "actions"

  private let control: ControlSpec
  private let labels: BundleLocalizationLabels
  private let rows: [ListRowSpec]
  private let bodyFontSize: CGFloat
  private weak var pageController: AppKitPageViewController?

  init(
    control: ControlSpec,
    labels: BundleLocalizationLabels,
    rows: [ListRowSpec],
    bodyFontSize: CGFloat,
    pageController: AppKitPageViewController
  ) {
    self.control = control
    self.labels = labels
    self.rows = rows
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
    let context = pageController.libraryCommandContext(for: row)
    let actions = control.rowActions.filter { $0.isVisible(resolving: context) }
    guard !actions.isEmpty else { return NSView() }
    let actionRow = pageController.actionRow(actions, context: context)
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
