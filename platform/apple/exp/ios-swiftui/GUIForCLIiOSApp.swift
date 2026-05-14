import Darwin
import Foundation
import SwiftUI

@main
struct GUIForCLIiOSApp: App {
  @StateObject private var textScale = AppTextScale()
  private let appLaunchTime = Date()

  var body: some Scene {
    WindowGroup {
      BundleBootstrapView(platformName: "iOS")
        .dynamicTypeSize(textScale.dynamicTypeSize)
        .onAppear {
          IOSStartupBenchmark.markWindowAppeared(since: appLaunchTime)
        }
    }
  }
}

@MainActor
private enum IOSStartupBenchmark {
  private static var didReport = false

  static func markWindowAppeared(since start: Date) {
    guard benchmarkEnabled, !didReport else {
      return
    }
    didReport = true
    let elapsed = Date().timeIntervalSince(start) * 1000
    print(String(format: "gfc-ios-swiftui benchmark window_appeared_ms=%.1f", elapsed))
    sendBenchmarkMarker(elapsedMilliseconds: elapsed)
    fflush(stdout)
  }

  private static var benchmarkEnabled: Bool {
    ProcessInfo.processInfo.arguments.contains("--benchmark")
      || ProcessInfo.processInfo.environment["GFC_BENCHMARK_STARTUP"] == "1"
  }

  private static func sendBenchmarkMarker(elapsedMilliseconds: Double) {
    guard let port = ProcessInfo.processInfo.environment["GFC_BENCHMARK_PORT"],
      let url = URL(
        string: String(
          format: "http://127.0.0.1:%@/ready?window_appeared_ms=%.1f",
          port,
          elapsedMilliseconds))
    else {
      return
    }
    URLSession.shared.dataTask(with: url).resume()
  }
}
