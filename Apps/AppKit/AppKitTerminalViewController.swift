import AppKit
import GUIForCLICore

@MainActor
final class AppKitTerminalViewController: NSViewController {
  private let model: AppKitTerminalModel
  private let labels: BundleLocalizationLabels
  private let tabPicker = NSPopUpButton()
  private let closeButton = NSButton(title: "Close", target: nil, action: nil)
  private let statusLabel = NSTextField(labelWithString: "")
  private let textView = NSTextView()
  private var renderedTabIDs: [UUID] = []
  private var renderedTabTitles: [String] = []
  private var renderedSelectedTabID: UUID?
  private var renderedSelectedLineCount = 0
  private var renderedSelectedStatusTitle = ""

  init(model: AppKitTerminalModel, labels: BundleLocalizationLabels) {
    self.model = model
    self.labels = labels
    super.init(nibName: nil, bundle: nil)
    model.onChange = { [weak self] in
      self?.reload()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    let root = NSView()

    let bar = NSStackView()
    bar.orientation = .horizontal
    bar.alignment = .centerY
    bar.spacing = 8
    bar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    bar.translatesAutoresizingMaskIntoConstraints = false

    let label = NSTextField(labelWithString: labels.terminalCommandOutputLabel)
    label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    tabPicker.target = self
    tabPicker.action = #selector(tabChanged)
    closeButton.target = self
    closeButton.action = #selector(closeSelectedTab)
    closeButton.setAccessibilityLabel("Close or cancel selected terminal tab")
    statusLabel.lineBreakMode = .byTruncatingTail

    bar.addArrangedSubview(label)
    bar.addArrangedSubview(tabPicker)
    bar.addArrangedSubview(statusLabel)
    bar.addArrangedSubview(closeButton)

    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    textView.isEditable = false
    textView.isSelectable = true
    textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    textView.textContainerInset = NSSize(width: 10, height: 10)
    textView.backgroundColor = .textBackgroundColor
    textView.setAccessibilityLabel(labels.terminalCommandOutputLabel)
    scrollView.documentView = textView

    root.addSubview(bar)
    root.addSubview(scrollView)
    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      bar.topAnchor.constraint(equalTo: root.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: bar.bottomAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])

    view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    reload()
  }

  @objc private func tabChanged() {
    let index = tabPicker.indexOfSelectedItem
    guard model.tabs.indices.contains(index) else { return }
    model.selectedTabID = model.tabs[index].id
  }

  @objc private func closeSelectedTab() {
    model.closeSelectedTab()
  }

  private func reload() {
    let selectedID = model.selectedTabID
    let tabIDs = model.tabs.map(\.id)
    let tabTitles = model.tabs.map(title(for:))
    let selectedTab = model.selectedTab
    let selectedStatusTitle = selectedTab?.status?.title ?? ""
    if canAppendSelectedTabLines(
      tabIDs: tabIDs,
      tabTitles: tabTitles,
      selectedID: selectedID,
      selectedTab: selectedTab,
      selectedStatusTitle: selectedStatusTitle)
    {
      appendSelectedTabLines(selectedTab)
      return
    }

    tabPicker.removeAllItems()
    for title in tabTitles {
      tabPicker.addItem(withTitle: title)
    }
    if let selectedIndex = model.tabs.firstIndex(where: { $0.id == selectedID }) {
      tabPicker.selectItem(at: selectedIndex)
    }

    closeButton.title = selectedTab?.isRunning == true ? "Cancel" : "Close"
    closeButton.isEnabled = selectedID != model.tabs.first?.id
    statusLabel.stringValue = selectedStatusTitle
    statusLabel.textColor = selectedTab?.status.map(statusColor) ?? .secondaryLabelColor
    statusLabel.toolTip = selectedTab?.status?.message
    textView.string = selectedTab?.lines.joined(separator: "\n") ?? ""
    textView.scrollToEndOfDocument(nil)
    renderedTabIDs = tabIDs
    renderedTabTitles = tabTitles
    renderedSelectedTabID = selectedID
    renderedSelectedLineCount = selectedTab?.lines.count ?? 0
    renderedSelectedStatusTitle = selectedStatusTitle
  }

  private func canAppendSelectedTabLines(
    tabIDs: [UUID],
    tabTitles: [String],
    selectedID: UUID?,
    selectedTab: AppKitTerminalTab?,
    selectedStatusTitle: String
  ) -> Bool {
    guard let selectedTab else { return false }
    return tabIDs == renderedTabIDs
      && tabTitles == renderedTabTitles
      && selectedID == renderedSelectedTabID
      && selectedStatusTitle == renderedSelectedStatusTitle
      && selectedTab.lines.count > renderedSelectedLineCount
  }

  private func appendSelectedTabLines(_ selectedTab: AppKitTerminalTab?) {
    guard let selectedTab else { return }
    let newLines = selectedTab.lines.dropFirst(renderedSelectedLineCount)
    guard !newLines.isEmpty else { return }
    let prefix = textView.string.isEmpty ? "" : "\n"
    textView.textStorage?.append(
      NSAttributedString(string: prefix + newLines.joined(separator: "\n")))
    textView.scrollToEndOfDocument(nil)
    renderedSelectedLineCount = selectedTab.lines.count
  }

  private func title(for tab: AppKitTerminalTab) -> String {
    if tab.isRunning {
      return "… \(tab.title)"
    }
    guard let status = tab.status else { return tab.title }
    switch status.severity {
    case .success:
      return "✓ \(tab.title)"
    case .warning:
      return "⚠ \(tab.title)"
    case .error:
      return "✕ \(tab.title)"
    case .cancelled:
      return "– \(tab.title)"
    }
  }

  private func statusColor(_ status: AppKitTerminalStatus) -> NSColor {
    switch status.severity {
    case .success:
      return .systemGreen
    case .warning:
      return .systemOrange
    case .error:
      return .systemRed
    case .cancelled:
      return .secondaryLabelColor
    }
  }
}
