import AppKit

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

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureApplicationMenu()

    let controller = AppKitWindowController()
    controller.showWindow(self)
    windowController = controller

    NSApp.activate(ignoringOtherApps: true)
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
