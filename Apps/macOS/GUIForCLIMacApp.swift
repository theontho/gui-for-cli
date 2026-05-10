import Foundation
import SwiftUI

@main
struct GUIForCLIMacApp: App {
  @StateObject private var textScale = AppTextScale()

  var body: some Scene {
    WindowGroup {
      ContentView(platformName: "macOS")
        .frame(minWidth: 840, minHeight: 680)
        .dynamicTypeSize(textScale.dynamicTypeSize)
        .onAppear {
          StartupBenchmark.markWindowAppeared()
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
  private static let start = Date()
  private static var didReport = false

  static func markWindowAppeared() {
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
      let existing = (try? String(contentsOfFile: outputPath, encoding: .utf8)) ?? ""
      try? "\(existing)\(message)\n".write(toFile: outputPath, atomically: true, encoding: .utf8)
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
}
