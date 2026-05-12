import AppKit
import GUIForCLICore

@MainActor
final class AppKitBundleBootstrapViewController: NSViewController {
  private let bundleRootURL: URL
  private let fallbackManifest: CLIBundleManifest?
  private var contentViewController: AppKitContentViewController?
  private var textScaleStep = 0

  init(
    bundleRootURL: URL = DemoBundle.wgsExtractResourceRootURL,
    fallbackManifest: CLIBundleManifest? = nil
  ) {
    self.bundleRootURL = bundleRootURL
    self.fallbackManifest = fallbackManifest
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760))
    view.autoresizingMask = [.width, .height]
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    showLoadingView()
    loadSession()
  }

  func adjustTextScale(by delta: Int) {
    textScaleStep = min(max(textScaleStep + delta, -3), 5)
    contentViewController?.textScaleStep = textScaleStep
  }

  func resetTextScale() {
    textScaleStep = 0
    contentViewController?.textScaleStep = textScaleStep
  }

  private func showLoadingView() {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false

    let indicator = NSProgressIndicator()
    indicator.style = .spinning
    indicator.controlSize = .large
    indicator.startAnimation(nil)

    let title = NSTextField(labelWithString: "Loading GUI for CLI...")
    title.font = .boldSystemFont(ofSize: 18)
    let message = NSTextField(labelWithString: "Preparing the sample bundle workspace.")
    message.textColor = .secondaryLabelColor

    stack.addArrangedSubview(indicator)
    stack.addArrangedSubview(title)
    stack.addArrangedSubview(message)

    view.subviews.forEach { $0.removeFromSuperview() }
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  private func loadSession() {
    let bundleRootURL = bundleRootURL
    let fallbackManifest = fallbackManifest
    Task {
      let session = await Task.detached(priority: .userInitiated) {
        BundleSessionLoader.bootstrap(
          sourceRootURL: bundleRootURL,
          fallbackManifest: fallbackManifest ?? DemoBundle.wgsExtract,
          systemPreferences: BundleSessionLoader.systemPreferredLocalizations())
      }.value
      showContent(session: session)
    }
  }

  private func showContent(session: BundleSession) {
    let controller = AppKitContentViewController(session: session)
    controller.textScaleStep = textScaleStep
    addChild(controller)
    view.subviews.forEach { $0.removeFromSuperview() }
    view.addSubview(controller.view)
    controller.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      controller.view.topAnchor.constraint(equalTo: view.topAnchor),
      controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    contentViewController = controller
  }

}
