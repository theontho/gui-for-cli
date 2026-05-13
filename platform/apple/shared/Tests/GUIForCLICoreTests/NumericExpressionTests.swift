import Foundation
import Testing

@testable import GUIForCLICore

@Test func evaluatesSimpleArithmetic() {
  #expect(NumericExpression.evaluate("1 + 2") == 3)
  #expect(NumericExpression.evaluate("10 / 4") == 2.5)
  #expect(NumericExpression.evaluate("2 * 3 + 4") == 10)
  #expect(NumericExpression.evaluate("2 + 3 * 4") == 14)
  #expect(NumericExpression.evaluate("(2 + 3) * 4") == 20)
  #expect(NumericExpression.evaluate("-5 + 3") == -2)
  #expect(NumericExpression.evaluate("1.5e2") == 150)
}

@Test func rejectsInvalidExpressions() {
  #expect(NumericExpression.evaluate("") == nil)
  #expect(NumericExpression.evaluate("abc") == nil)
  #expect(NumericExpression.evaluate("1 + ") == nil)
  #expect(NumericExpression.evaluate("(1 + 2") == nil)
  #expect(NumericExpression.evaluate("1 / 0") == nil)
  #expect(NumericExpression.evaluate("1 + 2 garbage") == nil)
}

@Test func parsesUnderscoreSeparators() {
  #expect(NumericExpression.evaluate("1_000_000") == 1_000_000)
}
