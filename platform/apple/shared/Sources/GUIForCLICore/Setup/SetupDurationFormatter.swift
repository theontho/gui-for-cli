import Foundation

public enum SetupDurationFormatter {
  public static func milliseconds(since start: Date, now: Date = Date()) -> Int {
    max(0, Int(now.timeIntervalSince(start) * 1000))
  }

  public static func text(_ durationMs: Int?) -> String {
    guard let durationMs else { return "" }
    return text(durationMs)
  }

  public static func text(_ durationMs: Int) -> String {
    let clampedDurationMs = max(0, durationMs)
    if clampedDurationMs < 1000 {
      return String(format: "%.1fs", Double(clampedDurationMs) / 1000)
    }
    let totalSeconds = max(0, Int((Double(clampedDurationMs) / 1000).rounded()))
    if totalSeconds < 60 {
      return "\(totalSeconds)s"
    }
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    if minutes < 60 {
      return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
    }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
  }
}
