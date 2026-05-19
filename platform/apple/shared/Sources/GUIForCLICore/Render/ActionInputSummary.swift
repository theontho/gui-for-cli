import Foundation

public enum ActionInputSummary {
  public static func describe(
    _ context: CommandRenderContext,
    command: CommandSpec? = nil
  ) -> String {
    var entries: [String] = []
    var seen: Set<String> = []
    if let command {
      for placeholder in command.inputPlaceholders() {
        appendEntry(for: placeholder, context: context, to: &entries, seen: &seen)
      }
    } else {
      appendEntries(context.fieldValues, context: context, to: &entries, seen: &seen)
      appendEntries(context.checkedOptions, context: context, to: &entries, seen: &seen)
      appendEntries(context.rowValues, context: context, to: &entries, seen: &seen)
      appendEntries(context.configValues, context: context, to: &entries, seen: &seen)
    }
    return entries.isEmpty ? "(none)" : entries.joined(separator: ", ")
  }

  private static func appendEntries(
    _ values: [String: String],
    context: CommandRenderContext,
    to entries: inout [String],
    seen: inout Set<String>
  ) {
    for key in values.keys.sorted() {
      let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !value.isEmpty else { continue }
      appendEntry(key: key, value: value, context: context, to: &entries, seen: &seen)
    }
  }

  private static func appendEntry(
    for placeholder: String,
    context: CommandRenderContext,
    to entries: inout [String],
    seen: inout Set<String>
  ) {
    let key = inputValueKey(placeholder)
    guard let value = context.value(for: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return
    }
    appendEntry(key: key, value: value, context: context, to: &entries, seen: &seen)
  }

  private static func appendEntry(
    key: String,
    value: String,
    context: CommandRenderContext,
    to entries: inout [String],
    seen: inout Set<String>
  ) {
    let label = label(for: key, context: context)
    let dedupeKey = "\(normalizedInputLabelKey(key))\u{0}\(label)\u{0}\(value)"
    guard !seen.contains(dedupeKey) else { return }
    seen.insert(dedupeKey)
    entries.append("\(label)=\(value)")
  }

  private static func label(for key: String, context: CommandRenderContext) -> String {
    context.label(for: key) ?? prettified(key)
  }

  private static func inputValueKey(_ placeholder: String) -> String {
    guard let separator = placeholder.lastIndex(of: "."),
      placeholder.index(after: separator) < placeholder.endIndex
    else {
      return placeholder
    }
    let suffix = placeholder[placeholder.index(after: separator)...]
    let fileStateSuffixes: Set<Substring> = [
      "exists", "fileSize", "fileSizeGB", "isIndexed", "isSorted", "pathExtension", "parentDir",
    ]
    return fileStateSuffixes.contains(suffix) ? String(placeholder[..<separator]) : placeholder
  }

  private static func normalizedInputLabelKey(_ key: String) -> String {
    var value = key
    if value.hasPrefix("row.") {
      value.removeFirst(4)
    } else if value.hasPrefix("config.") {
      value.removeFirst(7)
    }
    guard let separator = value.lastIndex(of: "."),
      value.index(after: separator) < value.endIndex
    else {
      return value
    }
    let suffix = value[value.index(after: separator)...]
    let fileStateSuffixes: Set<Substring> = [
      "exists", "fileSize", "fileSizeGB", "isIndexed", "isSorted", "pathExtension", "parentDir",
    ]
    return fileStateSuffixes.contains(suffix) ? String(value[..<separator]) : value
  }

  private static func prettified(_ key: String) -> String {
    var value = key
    if value.hasPrefix("row.") {
      value.removeFirst(4)
    } else if value.hasPrefix("config.") {
      value.removeFirst(7)
    }
    let words = value.split { character in
      character == "." || character == "_" || character == "-"
    }
    return words.map { word in
      word.prefix(1).uppercased() + word.dropFirst()
    }.joined(separator: " ")
  }
}
