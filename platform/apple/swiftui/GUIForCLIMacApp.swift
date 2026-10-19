import AppKit
import Foundation
import GUIForCLICore
import Sparkle
import SwiftUI
import UniformTypeIdentifiers

@main
struct GUIForCLIMacApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var textScale = AppTextScale()
  @State private var aboutMetadata = AppAboutMetadata()
  @FocusedValue(\.loadBundle) private var loadBundle
  private let updaterController = SparkleUpdaterController.make()
  private let appLaunchTime = Date()

  private var appDisplayName: String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
      ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
      ?? "GUI for CLI"
  }

  private var appWindowTitle: String {
    AppVersion.windowTitle(appDisplayName)
  }

  var body: some Scene {
    WindowGroup(appWindowTitle) {
      BundleBootstrapView(platformName: "macOS") { session in
        aboutMetadata.update(session: session)
      }
      .frame(minWidth: 840, minHeight: 680)
      .dynamicTypeSize(textScale.dynamicTypeSize)
      .onAppear {
        StartupBenchmark.markWindowAppeared(since: appLaunchTime)
      }
    }
    .commands {
      CommandGroup(replacing: .appInfo) {
        Button("About \(appDisplayName)") {
          NSApplication.shared.orderFrontStandardAboutPanel(
            options: aboutMetadata.aboutPanelOptions(applicationName: appDisplayName))
        }
      }

      CommandGroup(after: .appInfo) {
        Button("Check for Updates...") {
          updaterController?.checkForUpdates(nil)
        }
        .disabled(updaterController == nil)
      }

      CommandGroup(after: .newItem) {
        Button("Load Bundle...") {
          openBundlePanel()
        }
        .keyboardShortcut("o", modifiers: .command)
        .disabled(loadBundle == nil)
      }

      CommandGroup(after: .toolbar) {
        Divider()

        Button("Increase Text Size") {
          textScale.increase()
        }
        .keyboardShortcut("+", modifiers: .command)
        .disabled(!textScale.canIncrease)

        Button("Decrease Text Size") {
          textScale.decrease()
        }
        .keyboardShortcut("-", modifiers: .command)
        .disabled(!textScale.canDecrease)

        Divider()

        Button("Reset Text Size") {
          textScale.reset()
        }
        .keyboardShortcut("0", modifiers: .command)
        .disabled(!textScale.canReset)
      }
    }
  }

  /// Loads the chosen bundle into the window that was focused when the command ran.
  private func openBundlePanel() {
    guard let loadBundle else { return }
    let panel = NSOpenPanel()
    panel.message = String(localized: "Choose a bundle folder, manifest.json, or archive to load.")
    panel.prompt = String(localized: "Load")
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = Self.bundleContentTypes
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      loadBundle(url)
    }
  }

  private static var bundleContentTypes: [UTType] {
    [
      .directory,
      .json,
      .zip,
      .gzip,
      UTType(filenameExtension: "tgz"),
      UTType(filenameExtension: "tar"),
    ].compactMap(\.self)
  }
}

/// Terminates every supervised process tree before the app exits.
private final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationWillTerminate(_ notification: Notification) {
    ProcessSupervisor.shared.terminateAll(waitingUpTo: .seconds(2))
  }
}

@MainActor
private enum SparkleUpdaterController {
  static func make() -> SPUStandardUpdaterController? {
    guard
      let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
      !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
      !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return nil
    }
    return SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }
}
