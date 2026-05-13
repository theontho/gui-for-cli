import AppKit
import GUIForCLICore

@MainActor
final class AppKitSidebarViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate
{
  var onSelectPage: ((BundlePage) -> Void)?

  private let manifest: CLIBundleManifest
  private let tableView = NSTableView()
  private var selectedPageID: String?

  init(manifest: CLIBundleManifest, selectedPageID: String?) {
    self.manifest = manifest
    self.selectedPageID = selectedPageID
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    let root = NSView()

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false

    let header = NSStackView()
    header.orientation = .vertical
    header.alignment = .leading
    header.spacing = 4
    header.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 12, right: 16)

    let title = NSTextField(labelWithString: manifest.displayName)
    title.font = .boldSystemFont(ofSize: 16)
    title.lineBreakMode = .byTruncatingTail
    let summary = NSTextField(wrappingLabelWithString: manifest.summary)
    summary.textColor = .secondaryLabelColor
    summary.font = .systemFont(ofSize: 12)
    header.addArrangedSubview(title)
    header.addArrangedSubview(summary)

    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .noBorder
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.rowHeight = 36
    tableView.delegate = self
    tableView.dataSource = self
    tableView.selectionHighlightStyle = .sourceList
    scrollView.documentView = tableView

    stack.addArrangedSubview(header)
    stack.addArrangedSubview(scrollView)
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      stack.topAnchor.constraint(equalTo: root.topAnchor),
      stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])

    view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    if let selectedPageID,
      let index = manifest.pages.firstIndex(where: { $0.id == selectedPageID })
    {
      tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    manifest.pages.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard manifest.pages.indices.contains(row) else { return nil }
    let page = manifest.pages[row]
    let cell = NSTableCellView()
    let label = NSTextField(labelWithString: page.title)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.lineBreakMode = .byTruncatingTail
    cell.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
      label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    guard manifest.pages.indices.contains(row) else { return }
    selectedPageID = manifest.pages[row].id
    onSelectPage?(manifest.pages[row])
  }
}
