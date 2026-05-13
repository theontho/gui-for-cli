import GUIForCLICore
import SwiftUI

struct ActionPrecheckResult: Equatable {
  enum Severity { case info, warning }
  var severity: Severity
  var title: String
  var message: String
}

enum ActionPrecheckEvaluator {
  static func evaluate(
    spec: ActionPrecheckSpec,
    context: CommandRenderContext,
    labels: BundleLocalizationLabels
  ) -> ActionPrecheckResult? {
    guard let raw = spec.diskSpaceGB?.nonEmpty else { return nil }
    let interpolated = context.interpolated(raw)
    guard let requiredGB = NumericExpression.evaluate(interpolated), requiredGB > 0 else {
      return nil
    }
    let pathExpression = spec.diskSpacePath?.nonEmpty ?? "{{out_dir}}"
    var resolved =
      context
      .interpolated(pathExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if resolved.isEmpty {
      resolved = context.bundleRootPath ?? NSHomeDirectory()
    }
    let expanded = (resolved as NSString).expandingTildeInPath
    guard let availableGB = volumeAvailableGB(forPath: expanded) else {
      return nil
    }

    let formattedRequired = formatGB(requiredGB)
    let formattedAvailable = formatGB(availableGB)
    let pathLabel = diskPathLabel(forPath: expanded)
    let isLow = availableGB < requiredGB
    let title =
      isLow ? labels.actionPrecheckDiskSpaceTitle : labels.actionPrecheckDiskSpaceInfoTitle
    let format: String
    if let override = spec.warningMessage?.nonEmpty, isLow {
      format = context.interpolated(override)
    } else {
      format =
        isLow
        ? labels.actionPrecheckDiskSpaceMessageFormat
        : labels.actionPrecheckDiskSpaceInfoFormat
    }
    let message =
      format
      .replacingOccurrences(of: "%{required}", with: formattedRequired)
      .replacingOccurrences(of: "%{available}", with: formattedAvailable)
      .replacingOccurrences(of: "%{path}", with: pathLabel)
    return ActionPrecheckResult(
      severity: isLow ? .warning : .info, title: title, message: message)
  }

  private static func volumeAvailableGB(forPath path: String) -> Double? {
    let fileManager = FileManager.default
    var probe = path
    while !probe.isEmpty, !fileManager.fileExists(atPath: probe) {
      let parent = (probe as NSString).deletingLastPathComponent
      if parent == probe { break }
      probe = parent
    }
    guard !probe.isEmpty else { return nil }
    let url = URL(fileURLWithPath: probe)
    guard
      let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
      let bytes = values.volumeAvailableCapacityForImportantUsage
    else {
      // Fallback to plain available capacity.
      if let plain = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
        let bytes = plain.volumeAvailableCapacity
      {
        return Double(bytes) / 1_073_741_824.0
      }
      return nil
    }
    return Double(bytes) / 1_073_741_824.0
  }

  private static func diskPathLabel(forPath path: String) -> String {
    let url = URL(fileURLWithPath: path)
    let folderName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    guard let volumeName = volumeName(forPath: path), volumeName != folderName else {
      return folderName
    }
    return "\(folderName) (\(volumeName))"
  }

  private static func volumeName(forPath path: String) -> String? {
    let fileManager = FileManager.default
    var probe = path
    while !probe.isEmpty, !fileManager.fileExists(atPath: probe) {
      let parent = (probe as NSString).deletingLastPathComponent
      if parent == probe { break }
      probe = parent
    }
    guard !probe.isEmpty else { return nil }
    let url = URL(fileURLWithPath: probe)
    return try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName
  }

  private static func formatGB(_ value: Double) -> String {
    if value >= 100 {
      return String(format: "%.0f", value)
    }
    if value >= 10 {
      return String(format: "%.1f", value)
    }
    return String(format: "%.2f", value)
  }
}
