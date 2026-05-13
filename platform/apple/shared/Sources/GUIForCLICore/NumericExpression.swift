import Foundation

/// A tiny shunting-yard evaluator for placeholder math used in bundle specs.
///
/// Supported syntax:
/// - Decimal literals (with optional `_` digit groupings stripped).
/// - Binary operators `+`, `-`, `*`, `/` with C-style precedence.
/// - Parentheses for grouping.
/// - Unary `+` / `-`.
/// - Whitespace is ignored.
///
/// Returns `nil` if the input is empty, contains non-numeric tokens, or
/// represents an invalid expression. This intentionally does NOT evaluate
/// placeholders — the caller is expected to interpolate `{{...}}` first.
public enum NumericExpression {
  public static func evaluate(_ source: String) -> Double? {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    var parser = Parser(input: trimmed)
    let value = parser.parseExpression()
    return parser.atEnd ? value : nil
  }

  private struct Parser {
    let chars: [Character]
    var index: Int = 0

    init(input: String) {
      self.chars = Array(input)
    }

    var atEnd: Bool {
      mutating get {
        skipWhitespace()
        return index >= chars.count
      }
    }

    mutating func skipWhitespace() {
      while index < chars.count, chars[index].isWhitespace {
        index += 1
      }
    }

    mutating func parseExpression() -> Double? {
      parseAdditive()
    }

    mutating func parseAdditive() -> Double? {
      guard var lhs = parseMultiplicative() else { return nil }
      while true {
        skipWhitespace()
        guard index < chars.count else { return lhs }
        let op = chars[index]
        guard op == "+" || op == "-" else { return lhs }
        index += 1
        guard let rhs = parseMultiplicative() else { return nil }
        lhs = (op == "+") ? lhs + rhs : lhs - rhs
      }
    }

    mutating func parseMultiplicative() -> Double? {
      guard var lhs = parseUnary() else { return nil }
      while true {
        skipWhitespace()
        guard index < chars.count else { return lhs }
        let op = chars[index]
        guard op == "*" || op == "/" else { return lhs }
        index += 1
        guard let rhs = parseUnary() else { return nil }
        if op == "/" {
          guard rhs != 0 else { return nil }
          lhs = lhs / rhs
        } else {
          lhs = lhs * rhs
        }
      }
    }

    mutating func parseUnary() -> Double? {
      skipWhitespace()
      guard index < chars.count else { return nil }
      let ch = chars[index]
      if ch == "+" {
        index += 1
        return parseUnary()
      }
      if ch == "-" {
        index += 1
        guard let value = parseUnary() else { return nil }
        return -value
      }
      return parsePrimary()
    }

    mutating func parsePrimary() -> Double? {
      skipWhitespace()
      guard index < chars.count else { return nil }
      let ch = chars[index]
      if ch == "(" {
        index += 1
        guard let value = parseExpression() else { return nil }
        skipWhitespace()
        guard index < chars.count, chars[index] == ")" else { return nil }
        index += 1
        return value
      }
      return parseNumber()
    }

    mutating func parseNumber() -> Double? {
      skipWhitespace()
      let start = index
      while index < chars.count {
        let ch = chars[index]
        if ch.isNumber || ch == "." || ch == "_" || ch == "e" || ch == "E"
          || ((ch == "+" || ch == "-") && index > start
            && (chars[index - 1] == "e" || chars[index - 1] == "E"))
        {
          index += 1
        } else {
          break
        }
      }
      guard index > start else { return nil }
      let raw = String(chars[start..<index]).replacingOccurrences(of: "_", with: "")
      return Double(raw)
    }
  }
}
