import AppKit
import GUIForCLICore

@MainActor
final class AppKitContentViewController: NSViewController {
  var textScaleStep = 0 {
    didSet { pageViewController?.textScaleStep = textScaleStep }
  }

  private let session: BundleSession
  private let terminal: AppKitTerminalModel
  private lazy var state = AppKitBundleStateController(session: session) {
    [weak terminal] message in
    terminal?.appendToMain(message)
  }
  private let sidebarViewController: AppKitSidebarViewController
  private let terminalViewController: AppKitTerminalViewController
  private let rootSplit = NSSplitView()
  private let detailSplit = NSSplitView()
  private let detailContainer = NSView()
  private let terminalToggleButton = NSButton(title: "", target: nil, action: nil)
  private var pageViewController: AppKitPageViewController?
  private var terminalIsVisible = true
  private var didSetInitialTerminalPosition = false

  init(session: BundleSession) {
    self.session = session
    terminal = AppKitTerminalModel(
      labels: session.localizationLabels,
      exitCodeReference: session.manifest.effectiveExitCodeReference)
    sidebarViewController = AppKitSidebarViewController(
      manifest: session.manifest,
      selectedPageID: session.bundleState.selectedPageID ?? session.manifest.pages.first?.id)
    terminalViewController = AppKitTerminalViewController(
      model: terminal, labels: session.localizationLabels)
    super.init(nibName: nil, bundle: nil)
    sidebarViewController.onSelectPage = { [weak self] page in
      self?.selectPage(page)
    }
    terminal.onCommandComplete = { [weak self] _ in
      self?.pageViewController?.refreshDynamicDataAfterCommand()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760))
    root.autoresizingMask = [.width, .height]
    rootSplit.isVertical = true
    rootSplit.dividerStyle = .thin
    rootSplit.translatesAutoresizingMaskIntoConstraints = false

    let sidebar = sidebarViewController.view
    sidebar.translatesAutoresizingMaskIntoConstraints = false
    sidebar.widthAnchor.constraint(equalToConstant: 220).isActive = true

    detailSplit.isVertical = false
    detailSplit.dividerStyle = .thin
    detailSplit.translatesAutoresizingMaskIntoConstraints = false

    detailContainer.translatesAutoresizingMaskIntoConstraints = false
    terminalViewController.view.translatesAutoresizingMaskIntoConstraints = false
    terminalViewController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
      .isActive =
      true

    detailSplit.addArrangedSubview(detailContainer)
    detailSplit.addArrangedSubview(terminalViewController.view)
    rootSplit.addArrangedSubview(sidebar)
    rootSplit.addArrangedSubview(detailSplit)

    terminalToggleButton.target = self
    terminalToggleButton.action = #selector(toggleTerminal)
    terminalToggleButton.bezelStyle = .rounded
    terminalToggleButton.translatesAutoresizingMaskIntoConstraints = false
    updateTerminalToggleButton()

    root.addSubview(rootSplit)
    root.addSubview(terminalToggleButton)
    NSLayoutConstraint.activate([
      rootSplit.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      rootSplit.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      rootSplit.topAnchor.constraint(equalTo: root.topAnchor),
      rootSplit.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      terminalToggleButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
      terminalToggleButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
    ])

    view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    addChild(sidebarViewController)
    addChild(terminalViewController)

    for message in session.startupMessages {
      terminal.appendToMain(message)
    }

    let selectedPage =
      session.manifest.pages.first { $0.id == session.bundleState.selectedPageID }
      ?? session.manifest.pages.first
    if let selectedPage {
      selectPage(selectedPage)
    }
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    guard !didSetInitialTerminalPosition, detailSplit.bounds.height > 0 else { return }
    didSetInitialTerminalPosition = true
    detailSplit.setPosition(detailSplit.bounds.height * 0.76, ofDividerAt: 0)
  }

  private func selectPage(_ page: BundlePage) {
    state.persistSelectedPageID(page.id)
    pageViewController?.removeFromParent()
    detailContainer.subviews.forEach { $0.removeFromSuperview() }

    let controller = AppKitPageViewController(
      page: page,
      labels: session.localizationLabels,
      iconMap: session.iconMap,
      state: state,
      terminal: terminal,
      textScaleStep: textScaleStep)
    addChild(controller)
    detailContainer.addSubview(controller.view)
    controller.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      controller.view.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
      controller.view.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
      controller.view.topAnchor.constraint(equalTo: detailContainer.topAnchor),
      controller.view.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
    ])
    pageViewController = controller
  }

  @objc private func toggleTerminal() {
    terminalIsVisible.toggle()
    terminalViewController.view.isHidden = !terminalIsVisible
    updateTerminalToggleButton()
  }

  private func updateTerminalToggleButton() {
    let title =
      terminalIsVisible
      ? session.localizationLabels.terminalHideOutputLabel
      : session.localizationLabels.terminalShowOutputLabel
    terminalToggleButton.title = title
    terminalToggleButton.toolTip = title
    terminalToggleButton.setAccessibilityLabel(title)
  }
}
