import AppKit

final class AppKitWindowController: NSWindowController {
  private let bundleViewController = AppKitBundleBootstrapViewController()

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = AppKitAppIdentity.displayName
    window.titleVisibility = .visible
    window.titlebarAppearsTransparent = false
    window.minSize = NSSize(width: 840, height: 680)
    window.contentViewController = bundleViewController
    window.center()
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func adjustTextScale(by delta: Int) {
    bundleViewController.adjustTextScale(by: delta)
  }

  func resetTextScale() {
    bundleViewController.resetTextScale()
  }
}
