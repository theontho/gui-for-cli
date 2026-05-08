import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

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
      .replacingOccurrences(of: "%{path}", with: expanded)
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

struct ActionPrecheckBanner: View {
  let severity: ActionPrecheckResult.Severity
  let title: String
  let message: String

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: iconName)
        .foregroundStyle(accentColor)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.semibold))
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(accentColor.opacity(0.12))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(accentColor.opacity(0.45), lineWidth: 0.5)
    )
  }

  private var iconName: String {
    switch severity {
    case .info: "internaldrive"
    case .warning: "exclamationmark.triangle.fill"
    }
  }

  private var accentColor: Color {
    switch severity {
    case .info: .accentColor
    case .warning: .orange
    }
  }
}

struct RenderedCommand: Sendable {
  var executable: String
  var arguments: [String]

  var displayCommand: String {
    ([executable] + arguments).map(Self.shellQuoted).joined(separator: " ")
  }

  private static func shellQuoted(_ value: String) -> String {
    guard !value.isEmpty, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
      !value.contains("'")
    else {
      return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
    return value
  }
}

extension CommandSpec {
  func renderedCommand(resolving context: CommandRenderContext) -> RenderedCommand {
    let renderedOptionalArguments = optionalArguments.flatMap { group -> [String] in
      guard requiredPlaceholders(in: group, resolving: context).isEmpty else {
        return []
      }
      return group.map { interpolate($0, context: context) }
    }
    return RenderedCommand(
      executable: interpolate(executable, context: context),
      arguments: arguments.map { interpolate($0, context: context) } + renderedOptionalArguments
    )
  }

  func displayCommand(resolving context: CommandRenderContext) -> String {
    renderedCommand(resolving: context).displayCommand
  }

  func missingPlaceholders(resolving context: CommandRenderContext) -> [String] {
    requiredPlaceholders(in: [executable] + arguments, resolving: context)
  }

  private func requiredPlaceholders(in values: [String], resolving context: CommandRenderContext)
    -> [String]
  {
    var missing: [String] = []
    for placeholder in placeholders(in: values) {
      let value = context.value(for: placeholder)?.trimmingCharacters(in: .whitespacesAndNewlines)
      if value?.isEmpty != false, !missing.contains(placeholder) {
        missing.append(placeholder)
      }
    }
    return missing
  }

  private func interpolate(_ value: String, context: CommandRenderContext) -> String {
    var result = value
    let pattern = #"\{\{([^}]+)\}\}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return result
    }
    let matches = regex.matches(
      in: value,
      range: NSRange(value.startIndex..<value.endIndex, in: value))
    for match in matches.reversed() {
      guard
        let placeholderRange = Range(match.range(at: 1), in: value),
        let replacementRange = Range(match.range(at: 0), in: result)
      else {
        continue
      }
      let placeholder = String(value[placeholderRange]).trimmingCharacters(in: .whitespaces)
      result.replaceSubrange(replacementRange, with: context.value(for: placeholder) ?? "")
    }
    return result
  }

  private func placeholders(in values: [String]) -> [String] {
    let pattern = #"\{\{([^}]+)\}\}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return []
    }
    return values.flatMap { value in
      regex.matches(
        in: value,
        range: NSRange(value.startIndex..<value.endIndex, in: value)
      ).compactMap { match in
        guard let range = Range(match.range(at: 1), in: value) else {
          return nil
        }
        return String(value[range]).trimmingCharacters(in: .whitespaces)
      }
    }
  }
}

extension ActionSpec {
  func isVisible(resolving context: CommandRenderContext) -> Bool {
    visibleWhen.allSatisfy { $0.matches(resolving: context) }
  }

  func disabledReason(resolving context: CommandRenderContext) -> String? {
    guard disabledWhen.contains(where: { $0.matches(resolving: context) }) else {
      return nil
    }
    return disabledTooltip.map { context.interpolated($0) }.nonEmpty
      ?? "This action is not available."
  }
}

extension ActionConditionSpec {
  func matches(resolving context: CommandRenderContext) -> Bool {
    let value = context.value(for: placeholder) ?? ""
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if let exists {
      let hasValue = !trimmed.isEmpty
      if exists != hasValue {
        return false
      }
    }
    if let equals, trimmed != context.interpolated(equals) {
      return false
    }
    if let notEquals, trimmed == context.interpolated(notEquals) {
      return false
    }
    if !inValues.isEmpty
      && !inValues.map({ context.interpolated($0) }).contains(trimmed)
    {
      return false
    }
    if notInValues.map({ context.interpolated($0) }).contains(trimmed) {
      return false
    }
    if let lessThan, !Self.compareNumeric(trimmed, context.interpolated(lessThan), { $0 < $1 }) {
      return false
    }
    if let lessThanOrEqual,
      !Self.compareNumeric(trimmed, context.interpolated(lessThanOrEqual), { $0 <= $1 })
    {
      return false
    }
    if let greaterThan,
      !Self.compareNumeric(trimmed, context.interpolated(greaterThan), { $0 > $1 })
    {
      return false
    }
    if let greaterThanOrEqual,
      !Self.compareNumeric(trimmed, context.interpolated(greaterThanOrEqual), { $0 >= $1 })
    {
      return false
    }
    return true
  }

  private static func compareNumeric(
    _ left: String, _ right: String, _ op: (Double, Double) -> Bool
  ) -> Bool {
    guard
      let leftValue = NumericExpression.evaluate(left),
      let rightValue = NumericExpression.evaluate(right)
    else {
      return false
    }
    return op(leftValue, rightValue)
  }
}
