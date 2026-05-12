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
    section: PageSection,
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
      section: section,
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
