import Foundation

/// POSIX single-quote shell quoting for displayed and elevated commands.
public enum ShellQuoting {
  public static func quoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
  }

  public static func command(_ words: [String]) -> String {
    words.map(quoted).joined(separator: " ")
  }
}
