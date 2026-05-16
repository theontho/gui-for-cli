import AppKit
import Darwin

enum AppKitAppIdentity {
  static let displayName = "swift appkit test"
}

@main
@MainActor
enum AppKitMain {
  private static let retainedDelegate = AppKitAppDelegate()

  static func main() {
    let application = NSApplication.shared
    application.delegate = retainedDelegate
    application.setActivationPolicy(.regular)
    application.run()
  }
}

@MainActor
final class AppKitAppDelegate: NSObject, NSApplicationDelegate {
  private var windowController: AppKitWindowController?
  private let launchTime = Date()

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureApplicationMenu()

    let controller = AppKitWindowController()
    controller.showWindow(self)
    windowController = controller

    if ProcessInfo.processInfo.environment["GFC_BENCHMARK_PRESERVE_FOCUS"] != "1" {
      NSApp.activate(ignoringOtherApps: true)
    }
    AppKitStartupBenchmark.markWindowAppeared(since: launchTime)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  @objc private func increaseTextSize() {
    windowController?.adjustTextScale(by: 1)
  }

  @objc private func decreaseTextSize() {
    windowController?.adjustTextScale(by: -1)
  }

  @objc private func resetTextSize() {
    windowController?.resetTextScale()
  }

  private func configureApplicationMenu() {
    let mainMenu = NSMenu()
    let appItem = NSMenuItem()
    let viewItem = NSMenuItem()
    mainMenu.addItem(appItem)
    mainMenu.addItem(viewItem)

    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "Quit \(AppKitAppIdentity.displayName)",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    appItem.submenu = appMenu

    let viewMenu = NSMenu(title: "View")
    viewMenu.addItem(
      withTitle: "Increase Text Size",
      action: #selector(increaseTextSize),
      keyEquivalent: "+")
    viewMenu.addItem(
      withTitle: "Decrease Text Size",
      action: #selector(decreaseTextSize),
      keyEquivalent: "-")
    viewMenu.addItem(.separator())
    viewMenu.addItem(
      withTitle: "Reset Text Size",
      action: #selector(resetTextSize),
      keyEquivalent: "0")
    for item in viewMenu.items {
      item.target = self
    }
    viewItem.submenu = viewMenu

    NSApp.mainMenu = mainMenu
  }
}

@MainActor
private enum AppKitStartupBenchmark {
  private static var didReport = false

  static func markWindowAppeared(since start: Date) {
    guard benchmarkEnabled, !didReport else {
      return
    }
    didReport = true
    let elapsed = Date().timeIntervalSince(start) * 1000
    print(String(format: "gfc-appkit benchmark window_appeared_ms=%.1f", elapsed))
    fflush(stdout)
  }

  private static var benchmarkEnabled: Bool {
    ProcessInfo.processInfo.arguments.contains("--benchmark")
      || ProcessInfo.processInfo.environment["GFC_BENCHMARK_STARTUP"] == "1"
  }
}
