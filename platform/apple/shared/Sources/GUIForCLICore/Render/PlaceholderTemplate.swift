import Foundation

/// The one `{{placeholder}}` syntax used by commands, data sources, setup steps
/// and bundle paths. A placeholder is `{{` + one or more non-`}` characters + `}}`;
/// surrounding whitespace inside the braces is ignored.
public enum PlaceholderTemplate {
  /// Placeholder names in order of appearance (duplicates kept).
  public static func placeholders(in value: String) -> [String] {
    var names: [String] = []
    scan(value) { name, _ in names.append(name) }
    return names
  }

  /// Replaces each placeholder with `resolve(name)`. Unresolved placeholders
  /// become empty, or are kept verbatim when `keepingUnresolved` is set.
  public static func render(
    _ value: String,
    keepingUnresolved: Bool = false,
    resolve: (String) -> String?
  ) -> String {
    guard value.contains("{{") else { return value }
    var result = ""
    var cursor = value.startIndex
    scan(value) { name, range in
      result += value[cursor..<range.lowerBound]
      result += resolve(name) ?? (keepingUnresolved ? String(value[range]) : "")
      cursor = range.upperBound
    }
    result += value[cursor...]
    return result
  }

  private static func scan(_ value: String, _ visit: (String, Range<String.Index>) -> Void) {
    var searchStart = value.startIndex
    while let open = value.range(of: "{{", range: searchStart..<value.endIndex) {
      guard let close = value.range(of: "}}", range: open.upperBound..<value.endIndex) else {
        return
      }
      let inner = value[open.upperBound..<close.lowerBound]
      if inner.isEmpty || inner.contains("}") {
        // Not a placeholder; resume just after this "{{" like the regex `\{\{([^}]+)\}\}`.
        searchStart = value.index(after: open.lowerBound)
        continue
      }
      visit(inner.trimmingCharacters(in: .whitespaces), open.lowerBound..<close.upperBound)
      searchStart = close.upperBound
    }
  }
}
