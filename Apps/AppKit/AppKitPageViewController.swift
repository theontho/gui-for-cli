import AppKit
import GUIForCLICore

@MainActor
final class AppKitPageViewController: NSViewController {
  var textScaleStep: Int {
    didSet { renderPage() }
  }

  let page: BundlePage
  let labels: BundleLocalizationLabels
  let state: AppKitBundleStateController
  let terminal: AppKitTerminalModel
  var dynamicControls: [String: DynamicControlData] = [:]
  var dynamicErrors: [String: String] = [:]
  var sectionValues: [String: [String: String]] = [:]
  var loadingIDs: Set<String> = []
  let documentStack = AppKitViewFactory.verticalStack(spacing: 20)

  init(
    page: BundlePage,
    labels: BundleLocalizationLabels,
    state: AppKitBundleStateController,
    terminal: AppKitTerminalModel,
    textScaleStep: Int
  ) {
    self.page = page
    self.labels = labels
    self.state = state
    self.terminal = terminal
    self.textScaleStep = textScaleStep
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    documentStack.alignment = .leading
    let scrollView = AppKitViewFactory.scrollDocument(containing: documentStack)
    view = scrollView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    renderPage()
  }

  var bodyFontSize: CGFloat {
    NSFont.systemFontSize + CGFloat(textScaleStep)
  }

  func renderPage() {
    documentStack.arrangedSubviews.forEach { view in
      documentStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }

    let header = AppKitViewFactory.verticalStack(spacing: 8)
    let title = AppKitViewFactory.titleLabel(
      page.title, size: bodyFontSize + 12, weight: .semibold)
    let summary = AppKitViewFactory.secondaryLabel(page.summary, size: bodyFontSize)
    header.addArrangedSubview(title)
    header.addArrangedSubview(summary)
    summary.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true

    let headerActions = AppKitViewFactory.horizontalStack()
    let setupButton = NSButton(title: setupButtonTitle, target: self, action: #selector(runSetup))
    setupButton.isEnabled = !state.manifest.setup.steps.isEmpty
    let openButton = NSButton(
      title: labels.openBundleWorkspaceTitle,
      target: self,
      action: #selector(openBundleWorkspace))
    headerActions.addArrangedSubview(setupButton)
    headerActions.addArrangedSubview(openButton)
    header.addArrangedSubview(headerActions)
    addFullWidthSubview(header)

    for section in page.sections {
      addFullWidthSubview(sectionView(section))
      loadSectionDataIfNeeded(section)
    }
  }

  var setupButtonTitle: String {
    state.bundleState.setupRun == nil ? labels.setupRunButtonTitle : labels.setupRerunButtonTitle
  }

  func sectionView(_ section: PageSection) -> NSView {
    let stack = AppKitViewFactory.verticalStack(spacing: 14)

    if let subtitle = section.subtitle {
      stack.addArrangedSubview(AppKitViewFactory.secondaryLabel(subtitle, size: bodyFontSize))
    }

    for control in section.controls {
      let rendered = control.applying(dynamicControls[control.id] ?? DynamicControlData())
      stack.addArrangedSubview(controlView(rendered))
      loadControlDataIfNeeded(control, in: section)
      if let error = dynamicErrors[control.id] {
        stack.addArrangedSubview(AppKitViewFactory.secondaryLabel(error, size: bodyFontSize - 1))
      }
    }

    if !section.actions.isEmpty {
      let separator = NSBox()
      separator.boxType = .separator
      stack.addArrangedSubview(separator)
      stack.addArrangedSubview(actionRow(section.actions, context: commandContext(for: section)))
    }

    if let error = dynamicErrors[section.id] {
      stack.addArrangedSubview(AppKitViewFactory.secondaryLabel(error, size: bodyFontSize - 1))
    }

    return AppKitViewFactory.boxed(title: section.title, content: stack)
  }

  private func addFullWidthSubview(_ view: NSView) {
    documentStack.addArrangedSubview(view)
    view.widthAnchor.constraint(equalTo: documentStack.widthAnchor).isActive = true
  }
}
