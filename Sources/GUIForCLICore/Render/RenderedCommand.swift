import Foundation

public struct RenderedCommand: Sendable {
  public var executable: String
  public var arguments: [String]

  public init(executable: String, arguments: [String]) {
    self.executable = executable
    self.arguments = arguments
  }

  public var displayCommand: String {
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

public extension CommandSpec {
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

public extension ActionSpec {
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

public extension ActionConditionSpec {
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
