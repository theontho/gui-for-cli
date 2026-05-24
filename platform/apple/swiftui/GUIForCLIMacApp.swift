import AppKit
import Darwin
import Foundation
import GUIForCLICore
import Sparkle
import SwiftUI

@main
struct GUIForCLIMacApp: App {
  @NSApplicationDelegateAdaptor(GUIForCLIMacAppDelegate.self) private var appDelegate
  @StateObject private var textScale = AppTextScale()
  private let appLaunchTime = Date()

  private var appWindowTitle: String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
      ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
      ?? "GUI for CLI"
  }

  var body: some Scene {
    WindowGroup(appWindowTitle) {
      BundleBootstrapView(platformName: "macOS")
        .frame(minWidth: 840, minHeight: 680)
        .dynamicTypeSize(textScale.dynamicTypeSize)
        .onAppear {
          StartupBenchmark.markWindowAppeared(since: appLaunchTime)
        }
    }
    .commands {
      CommandGroup(replacing: .appInfo) {
        Button("About \(appWindowTitle)") {
          let version = DemoBundle.defaultManifest.version ?? ""
          let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationVersion: version,
          ]
          NSApplication.shared.orderFrontStandardAboutPanel(options: options)
        }
      }

      CommandGroup(after: .appInfo) {
        Button("Check for Updates...") {
          appDelegate.updaterController?.checkForUpdates(nil)
        }
        .disabled(appDelegate.updaterController == nil)
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
}

@MainActor
final class GUIForCLIMacAppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
  lazy var updaterController = SparkleUpdaterController.make(
    updaterDelegate: self)

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    sparkleDebugLog("found update \(item.versionString)")
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
    sparkleDebugLog("no update found: \(error)")
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    sparkleDebugLog("aborted: \(error)")
  }

  func updater(
    _ updater: SPUUpdater,
    didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
    error: Error?
  ) {
    if let error {
      sparkleDebugLog("finished update cycle with error: \(error)")
    } else {
      sparkleDebugLog("finished update cycle")
    }
  }

  private func sparkleDebugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["GFC_SPARKLE_DEBUG"] == "1" else {
      return
    }
    fputs("gfc-sparkle \(message)\n", stderr)
  }
}

@MainActor
private enum SparkleUpdaterController {
  static func make(
    updaterDelegate: SPUUpdaterDelegate
  ) -> SPUStandardUpdaterController? {
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
      updaterDelegate: updaterDelegate,
      userDriverDelegate: nil
    )
  }
}

@MainActor
private enum StartupBenchmark {
  private static var didReport = false

  static func markWindowAppeared(since start: Date) {
    let benchmarkOutputPath = Self.benchmarkOutputPath()
    guard
      benchmarkOutputPath != nil
        || ProcessInfo.processInfo.environment["GFC_BENCHMARK_STARTUP"] == "1",
      !didReport
    else {
      return
    }
    didReport = true
    let elapsed = Date().timeIntervalSince(start) * 1000
    let message = String(format: "gfc-swiftui benchmark window_appeared_ms=%.1f", elapsed)
    print(message)
    if let outputPath = benchmarkOutputPath {
      appendBenchmarkMessage(message, to: outputPath)
    }
    fflush(stdout)
  }

  private static func benchmarkOutputPath() -> String? {
    let arguments = ProcessInfo.processInfo.arguments
    if let index = arguments.firstIndex(of: "--benchmark-output"),
      arguments.indices.contains(arguments.index(after: index))
    {
      return arguments[arguments.index(after: index)]
    }
    return ProcessInfo.processInfo.environment["GFC_BENCHMARK_OUTPUT"]
  }

  private static func appendBenchmarkMessage(_ message: String, to outputPath: String) {
    let mode = mode_t(S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
    let fd = open(outputPath, O_CREAT | O_WRONLY | O_APPEND, mode)
    guard fd >= 0 else {
      logWriteFailure("open", outputPath: outputPath)
      return
    }
    defer {
      if close(fd) != 0 {
        logWriteFailure("close", outputPath: outputPath)
      }
    }

    let bytes = Array((message + "\n").utf8)
    let didWrite = bytes.withUnsafeBytes { buffer -> Bool in
      guard let baseAddress = buffer.baseAddress else {
        return true
      }
      var offset = 0
      while offset < buffer.count {
        let written = write(fd, baseAddress.advanced(by: offset), buffer.count - offset)
        if written < 0 {
          return false
        }
        offset += written
      }
      return true
    }

    if !didWrite {
      logWriteFailure("write", outputPath: outputPath)
    }
  }

  private static func logWriteFailure(_ operation: String, outputPath: String) {
    let errorMessage = String(cString: strerror(errno))
    fputs(
      "gfc-swiftui benchmark write_failed: \(operation) \(outputPath): \(errorMessage)\n",
      stderr)
  }
}
