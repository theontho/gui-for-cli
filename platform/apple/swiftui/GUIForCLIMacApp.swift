import Darwin
import Foundation
import SwiftUI

@main
struct GUIForCLIMacApp: App {
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
