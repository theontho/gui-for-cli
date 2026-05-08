#!/usr/bin/env swift
import CommonCrypto
import Darwin
import Foundation

// Dev tool: lint GUI-for-CLI bundle localization TOML files.
//
// Usage:
//   swift scripts/lint-locales.swift [--strict] [--json] [--update-source-hashes] [PATH ...]
//
// - PATH may be a bundle directory (containing strings/strings.toml), a strings.toml file,
//   or omitted to auto-scan Examples/*/strings/strings.toml in the repo root.
// - Reports parse errors, missing/extra/empty/duplicate keys, missing built-in
//   keys the runtime expects, invalid layoutDirection, and likely-untranslated
//   values (target string identical to English source).
// - Detects translation drift: when a translated line carries an
//   `i18n-source-hash:<hex>` annotation whose hash no longer matches the
//   current English source value, emits a `source-changed` warning.
// - `--update-source-hashes` rewrites locale files in place, stamping each
//   translated line with the current source hash. Use this after retranslating.
// - Exits non-zero if any errors are found. With --strict, warnings also fail.
// - To intentionally suppress an "untranslated" warning on a line (e.g. a proper
//   noun reused verbatim), append a trailing `# i18n-ignore` comment, e.g.:
//       "bundle.displayName" = "WGS Extract"  # i18n-ignore

// MARK: - Built-in keys

// Keys the runtime always looks up via BundleLocalizationLabels and the default
// exit-code reference table. Locales should provide all of these even if the
// source strings.toml does not.
private let builtinRequiredKeys: [String] = [
  "language.code",
  "language.name",
  "language.setting.title",
  "language.setting.label",
  "language.setting.searchPlaceholder",
  "language.setting.systemDefault",
  "language.layoutDirection",
  "app.terminal.mainTab.title",
  "app.terminal.commandOutput.label",
  "app.pathPicker.chooseButton.title",
  "app.pathPicker.error.title",
  "app.settingsFile.label",
  "app.loadButton.title",
  "app.actionsColumn.title",
  "app.loading.title",
  "app.refreshing.title",
  "app.retryButton.title",
  "app.action.precheck.diskSpace.title",
  "app.action.precheck.diskSpace.messageFormat",
  "library.status.installed",
  "library.status.unindexed",
  "library.status.incomplete",
  "library.status.missing",
  "library.tags.recommended",
  "exitCodes.default.1.title",
  "exitCodes.default.1.summary",
  "exitCodes.default.2.title",
  "exitCodes.default.2.summary",
  "exitCodes.default.126.title",
  "exitCodes.default.126.summary",
  "exitCodes.default.127.title",
  "exitCodes.default.127.summary",
  "exitCodes.default.130.title",
  "exitCodes.default.130.summary",
]

private let validLayoutDirections: Set<String> = ["ltr", "rtl"]

// MARK: - CLI args

private struct Arguments {
  var strict = false
  var json = false
  var updateSourceHashes = false
  var paths: [String] = []
}

private func parseArguments() -> Arguments {
  var args = Arguments()
  var iterator = CommandLine.arguments.dropFirst().makeIterator()
  while let arg = iterator.next() {
    switch arg {
    case "--strict": args.strict = true
    case "--json": args.json = true
    case "--update-source-hashes": args.updateSourceHashes = true
    case "-h", "--help":
      printUsage()
      exit(0)
    default:
      if arg.hasPrefix("-") {
        FileHandle.standardError.write(Data("Unknown flag: \(arg)\n".utf8))
        printUsage()
        exit(2)
      }
      args.paths.append(arg)
    }
  }
  return args
}

private func printUsage() {
  let text = """
    Usage: swift scripts/lint-locales.swift [--strict] [--json] [PATH ...]

    Lints localization TOML files for GUI-for-CLI bundles.

    Options:
      --strict   Treat warnings (untranslated values, extra keys) as errors.
      --json     Emit a machine-readable JSON report instead of plain text.
      -h, --help Show this help.

    PATH may be a bundle directory containing strings.toml, a strings.toml file,
    or omitted to auto-scan Examples/*/strings.toml relative to the current
    working directory.

    Annotate intentional verbatim reuse with a trailing comment:
      "bundle.displayName" = "WGS Extract"  # i18n-ignore
    """
  print(text)
}

// MARK: - TOML parsing (line-aware)

private struct ParsedEntry {
  let key: String
  let value: String
  let line: Int
  let ignoreUntranslated: Bool
  /// Recorded source hash from a trailing `i18n-source-hash:<hex>` annotation,
  /// if present.
  let recordedSourceHash: String?
}

private struct ParsedFile {
  let url: URL
  var entries: [ParsedEntry] = []
  var duplicateKeys: [(key: String, line: Int, previousLine: Int)] = []
  var parseErrors: [(line: Int, message: String)] = []
  var keyIndex: [String: Int] = [:]  // key -> index into entries

  func value(for key: String) -> String? {
    keyIndex[key].map { entries[$0].value }
  }
  func line(for key: String) -> Int? {
    keyIndex[key].map { entries[$0].line }
  }
}

private func parseTOMLFile(at url: URL) -> ParsedFile {
  var parsed = ParsedFile(url: url)
  guard let data = try? Data(contentsOf: url),
    let text = String(data: data, encoding: .utf8)
  else {
    parsed.parseErrors.append((0, "Could not read file as UTF-8"))
    return parsed
  }

  let lines = text.components(separatedBy: "\n")
  var index = 0
  while index < lines.count {
    let rawLine = lines[index]
    let lineNumber = index + 1
    index += 1
    let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

    guard let eq = trimmed.firstIndex(of: "=") else {
      parsed.parseErrors.append((lineNumber, "Missing `=` separator: \(trimmed)"))
      continue
    }

    let rawKey = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
    let rawValueAndComment = String(trimmed[trimmed.index(after: eq)...])
      .trimmingCharacters(in: .whitespaces)
    let key = unquoteKey(rawKey)
    if key.isEmpty {
      parsed.parseErrors.append((lineNumber, "Empty key"))
      continue
    }

    // Multiline strings (""" ... """) — collect across lines, no comment support.
    if rawValueAndComment.hasPrefix("\"\"\"") {
      let body = String(rawValueAndComment.dropFirst(3))
      var collected: [String] = []
      if let end = body.range(of: "\"\"\"") {
        collected.append(String(body[..<end.lowerBound]))
      } else {
        collected.append(body)
        var foundEnd = false
        while index < lines.count {
          let next = lines[index]
          index += 1
          if let end = next.range(of: "\"\"\"") {
            collected.append(String(next[..<end.lowerBound]))
            foundEnd = true
            break
          }
          collected.append(next)
        }
        if !foundEnd {
          parsed.parseErrors.append(
            (lineNumber, "Unterminated multiline string for key \(key)"))
          continue
        }
      }
      if collected.first == "" { collected.removeFirst() }
      if collected.last == "" { collected.removeLast() }
      let value = collected.joined(separator: "\n")
      record(
        key: key, value: value, line: lineNumber, ignoreUntranslated: false,
        recordedSourceHash: nil, parsed: &parsed)
      continue
    }

    // Single-line "value"  optionally followed by `# comment`
    var (valueLiteral, comment) = splitValueAndComment(rawValueAndComment)
    valueLiteral = valueLiteral.trimmingCharacters(in: .whitespaces)
    guard valueLiteral.hasPrefix("\""), valueLiteral.hasSuffix("\""),
      valueLiteral.count >= 2
    else {
      parsed.parseErrors.append(
        (lineNumber, "Value must be a double-quoted string: \(valueLiteral)"))
      continue
    }
    let inner = String(valueLiteral.dropFirst().dropLast())
    let value = unescape(inner)
    let lowerComment = comment.lowercased()
    let ignoreUntranslated = lowerComment.contains("i18n-ignore")
    let recordedHash = extractSourceHash(from: comment)
    record(
      key: key, value: value, line: lineNumber, ignoreUntranslated: ignoreUntranslated,
      recordedSourceHash: recordedHash, parsed: &parsed)
  }
  return parsed
}

private func record(
  key: String, value: String, line: Int, ignoreUntranslated: Bool,
  recordedSourceHash: String?, parsed: inout ParsedFile
) {
  if let existing = parsed.keyIndex[key] {
    parsed.duplicateKeys.append(
      (key: key, line: line, previousLine: parsed.entries[existing].line))
  }
  let entry = ParsedEntry(
    key: key, value: value, line: line, ignoreUntranslated: ignoreUntranslated,
    recordedSourceHash: recordedSourceHash)
  parsed.keyIndex[key] = parsed.entries.count
  parsed.entries.append(entry)
}

/// Extracts the hex hash from `i18n-source-hash:<hex>` markers in a comment.
private func extractSourceHash(from comment: String) -> String? {
  guard let range = comment.range(of: "i18n-source-hash:", options: .caseInsensitive) else {
    return nil
  }
  let after = comment[range.upperBound...]
  let hexChars = after.prefix { ch in ch.isHexDigit }
  return hexChars.isEmpty ? nil : String(hexChars).lowercased()
}

private func splitValueAndComment(_ raw: String) -> (value: String, comment: String) {
  // Walk the string; honor escaped quotes; first unescaped `#` outside the
  // closing quote starts a trailing comment.
  var inString = false
  var escaped = false
  var splitAt: String.Index? = nil
  for index in raw.indices {
    let character = raw[index]
    if escaped {
      escaped = false
      continue
    }
    if character == "\\" {
      escaped = true
      continue
    }
    if character == "\"" {
      inString.toggle()
      continue
    }
    if character == "#" && !inString {
      splitAt = index
      break
    }
  }
  guard let splitAt else { return (raw, "") }
  let value = raw[..<splitAt].trimmingCharacters(in: .whitespaces)
  let comment = raw[splitAt...].trimmingCharacters(in: .whitespaces)
  return (value, comment)
}

private func unquoteKey(_ key: String) -> String {
  if key.hasPrefix("\"") && key.hasSuffix("\"") && key.count >= 2 {
    return String(key.dropFirst().dropLast())
  }
  return key
}

private func unescape(_ value: String) -> String {
  var result = ""
  var iterator = value.makeIterator()
  while let character = iterator.next() {
    guard character == "\\" else {
      result.append(character)
      continue
    }
    guard let escaped = iterator.next() else {
      result.append("\\")
      break
    }
    switch escaped {
    case "n": result.append("\n")
    case "r": result.append("\r")
    case "t": result.append("\t")
    case "\"": result.append("\"")
    case "\\": result.append("\\")
    default:
      result.append("\\")
      result.append(escaped)
    }
  }
  return result
}

// MARK: - Findings

private enum Severity: String { case error, warning }

private struct Finding {
  let severity: Severity
  let code: String
  let line: Int?
  let key: String?
  let message: String
}

private struct LocaleReport {
  let bundleName: String
  let localeCode: String
  let url: URL
  let totalKeys: Int
  let findings: [Finding]
  var errorCount: Int { findings.filter { $0.severity == .error }.count }
  var warningCount: Int { findings.filter { $0.severity == .warning }.count }
}

// MARK: - Linter

private func lintLocale(
  source: ParsedFile,
  target: ParsedFile,
  bundleName: String,
  localeCode: String
) -> LocaleReport {
  var findings: [Finding] = []

  for parseError in target.parseErrors {
    findings.append(
      Finding(
        severity: .error, code: "parse-error", line: parseError.line, key: nil,
        message: parseError.message))
  }
  for dup in target.duplicateKeys {
    findings.append(
      Finding(
        severity: .error, code: "duplicate-key", line: dup.line, key: dup.key,
        message: "Duplicate key (previously defined on line \(dup.previousLine))"))
  }

  let sourceKeys = Set(source.entries.map(\.key))
  let targetKeys = Set(target.entries.map(\.key))
  let requiredKeys = sourceKeys.union(builtinRequiredKeys)

  // Missing keys
  for missing in requiredKeys.subtracting(targetKeys).sorted() {
    let isBuiltin = builtinRequiredKeys.contains(missing) && !sourceKeys.contains(missing)
    let label = isBuiltin ? "missing-builtin-key" : "missing-key"
    let detail =
      isBuiltin ? "Required built-in key not provided" : "Key present in source is missing"
    findings.append(
      Finding(severity: .error, code: label, line: nil, key: missing, message: detail))
  }

  // Extra keys (in target but neither in source nor a built-in) — warning
  for extra in targetKeys.subtracting(requiredKeys).sorted() {
    findings.append(
      Finding(
        severity: .warning, code: "extra-key", line: target.line(for: extra), key: extra,
        message: "Key not present in source strings.toml or built-in list"))
  }

  // Per-entry checks
  for entry in target.entries {
    if entry.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      findings.append(
        Finding(
          severity: .error, code: "empty-value", line: entry.line, key: entry.key,
          message: "Empty translation value"))
    }

    if entry.key == "language.layoutDirection" {
      let normalized = entry.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if !validLayoutDirections.contains(normalized) {
        findings.append(
          Finding(
            severity: .error, code: "invalid-layout-direction", line: entry.line,
            key: entry.key,
            message: "language.layoutDirection must be \"ltr\" or \"rtl\" (got \"\(entry.value)\")"
          ))
      }
      continue
    }

    if entry.key == "language.code" {
      let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed != localeCode {
        findings.append(
          Finding(
            severity: .error, code: "language-code-mismatch", line: entry.line,
            key: entry.key,
            message:
              "language.code is \"\(trimmed)\" but file is \"strings.\(localeCode).toml\""))
      }
      continue
    }

    if entry.key == "language.name" { continue }

    if let sourceValue = source.value(for: entry.key),
      sourceValue == entry.value,
      !entry.ignoreUntranslated,
      !entry.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      findings.append(
        Finding(
          severity: .warning, code: "untranslated", line: entry.line, key: entry.key,
          message: "Value matches English source verbatim (add `# i18n-ignore` if intentional)"))
    }

    if let sourceValue = source.value(for: entry.key),
      let recordedHash = entry.recordedSourceHash,
      recordedHash != shortSourceHash(of: sourceValue)
    {
      findings.append(
        Finding(
          severity: .warning, code: "source-changed", line: entry.line, key: entry.key,
          message:
            "Source string has changed since translation; retranslate then run --update-source-hashes"
        ))
    }
  }

  return LocaleReport(
    bundleName: bundleName, localeCode: localeCode, url: target.url,
    totalKeys: target.entries.count, findings: findings)
}

// MARK: - Discovery

private struct BundleTarget {
  let name: String
  let directory: URL
  let sourceURL: URL
  let localeURLs: [(code: String, url: URL)]
}

private func discoverBundles(paths: [String]) -> [BundleTarget] {
  let fileManager = FileManager.default
  var sources: [URL] = []

  func resolveBundleDir(_ url: URL) -> URL? {
    let nested = url.appendingPathComponent("strings", isDirectory: true)
      .appendingPathComponent("strings.toml", isDirectory: false)
    return fileManager.fileExists(atPath: nested.path) ? nested : nil
  }

  if paths.isEmpty {
    let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
    let examplesDir = cwd.appendingPathComponent("Examples", isDirectory: true)
    if let contents = try? fileManager.contentsOfDirectory(
      at: examplesDir, includingPropertiesForKeys: nil)
    {
      for url in contents.sorted(by: { $0.path < $1.path }) {
        if let candidate = resolveBundleDir(url) {
          sources.append(candidate)
        }
      }
    }
  } else {
    for path in paths {
      let url = URL(fileURLWithPath: path)
      var isDir: ObjCBool = false
      guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
        FileHandle.standardError.write(Data("Path does not exist: \(path)\n".utf8))
        continue
      }
      if isDir.boolValue {
        if let candidate = resolveBundleDir(url) {
          sources.append(candidate)
        } else {
          FileHandle.standardError.write(
            Data("No strings/strings.toml in \(url.path)\n".utf8))
        }
      } else {
        sources.append(url)
      }
    }
  }

  var bundles: [BundleTarget] = []
  for source in sources {
    let stringsDirectory = source.deletingLastPathComponent()
    let bundleName = stringsDirectory.deletingLastPathComponent().lastPathComponent
    var locales: [(String, URL)] = []
    if let contents = try? fileManager.contentsOfDirectory(
      at: stringsDirectory, includingPropertiesForKeys: nil)
    {
      for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let name = url.lastPathComponent
        guard name.hasPrefix("strings."), name.hasSuffix(".toml"), name != "strings.toml"
        else { continue }
        let inner = String(name.dropFirst("strings.".count).dropLast(".toml".count))
        locales.append((inner, url))
      }
    }
    bundles.append(
      BundleTarget(
        name: bundleName, directory: stringsDirectory, sourceURL: source, localeURLs: locales))
  }
  return bundles
}

// MARK: - Reporting

private let isTTY = isatty(fileno(stdout)) != 0
private func color(_ text: String, _ ansi: String) -> String {
  isTTY ? "\u{001B}[\(ansi)m\(text)\u{001B}[0m" : text
}

private func printTextReport(
  bundles: [(BundleTarget, [LocaleReport], [Finding])], strict: Bool
) -> Bool {
  var hadError = false
  for (bundle, locales, sourceFindings) in bundles {
    print(color("=== \(bundle.name) (\(bundle.directory.path))", "1;36"))
    if !sourceFindings.isEmpty {
      print(color("  source strings.toml:", "1"))
      for finding in sourceFindings {
        printFinding(finding, indent: "    ")
        if finding.severity == .error || strict { hadError = true }
      }
    }
    if locales.isEmpty {
      print("  (no locale files found)")
      continue
    }
    for report in locales {
      let summary =
        "  [\(report.localeCode)] \(report.totalKeys) keys, "
        + "\(report.errorCount) errors, \(report.warningCount) warnings"
      let coloredSummary: String
      if report.errorCount > 0 {
        coloredSummary = color(summary, "31")
      } else if report.warningCount > 0 {
        coloredSummary = color(summary, "33")
      } else {
        coloredSummary = color(summary, "32")
      }
      print(coloredSummary)
      for finding in report.findings {
        printFinding(finding, indent: "    ")
      }
      if report.errorCount > 0 { hadError = true }
      if strict && report.warningCount > 0 { hadError = true }
    }
  }
  return hadError
}

private func printFinding(_ finding: Finding, indent: String) {
  let tag: String
  switch finding.severity {
  case .error: tag = color("error", "31")
  case .warning: tag = color("warn ", "33")
  }
  var location = ""
  if let line = finding.line { location += ":\(line)" }
  var keyPart = ""
  if let key = finding.key { keyPart = " [\(key)]" }
  print("\(indent)\(tag) \(finding.code)\(location)\(keyPart) — \(finding.message)")
}

private func emitJSON(
  bundles: [(BundleTarget, [LocaleReport], [Finding])], strict: Bool
) -> Bool {
  var hadError = false
  var bundlesPayload: [[String: Any]] = []
  for (bundle, locales, sourceFindings) in bundles {
    var localesPayload: [[String: Any]] = []
    for finding in sourceFindings {
      if finding.severity == .error || strict { hadError = true }
    }
    for report in locales {
      if report.errorCount > 0 { hadError = true }
      if strict && report.warningCount > 0 { hadError = true }
      localesPayload.append([
        "code": report.localeCode,
        "path": report.url.path,
        "totalKeys": report.totalKeys,
        "errors": report.errorCount,
        "warnings": report.warningCount,
        "findings": report.findings.map(jsonFinding),
      ])
    }
    bundlesPayload.append([
      "name": bundle.name,
      "path": bundle.directory.path,
      "source": bundle.sourceURL.path,
      "sourceFindings": sourceFindings.map(jsonFinding),
      "locales": localesPayload,
    ])
  }
  let payload: [String: Any] = ["bundles": bundlesPayload, "ok": !hadError]
  if let data = try? JSONSerialization.data(
    withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
    let json = String(data: data, encoding: .utf8)
  {
    print(json)
  }
  return hadError
}

private func jsonFinding(_ finding: Finding) -> [String: Any] {
  var dict: [String: Any] = [
    "severity": finding.severity.rawValue,
    "code": finding.code,
    "message": finding.message,
  ]
  if let line = finding.line { dict["line"] = line }
  if let key = finding.key { dict["key"] = key }
  return dict
}

// MARK: - Source-file checks

private func lintSource(_ source: ParsedFile) -> [Finding] {
  var findings: [Finding] = []
  for parseError in source.parseErrors {
    findings.append(
      Finding(
        severity: .error, code: "parse-error", line: parseError.line, key: nil,
        message: parseError.message))
  }
  for dup in source.duplicateKeys {
    findings.append(
      Finding(
        severity: .error, code: "duplicate-key", line: dup.line, key: dup.key,
        message: "Duplicate key (previously defined on line \(dup.previousLine))"))
  }
  let keys = Set(source.entries.map(\.key))
  for required in builtinRequiredKeys where !keys.contains(required) {
    findings.append(
      Finding(
        severity: .error, code: "missing-builtin-key", line: nil, key: required,
        message: "Source strings.toml is missing required built-in key"))
  }
  for entry in source.entries {
    if entry.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      findings.append(
        Finding(
          severity: .error, code: "empty-value", line: entry.line, key: entry.key,
          message: "Empty value in source strings.toml"))
    }
    if entry.key == "language.layoutDirection" {
      let normalized = entry.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if !validLayoutDirections.contains(normalized) {
        findings.append(
          Finding(
            severity: .error, code: "invalid-layout-direction", line: entry.line,
            key: entry.key,
            message: "language.layoutDirection must be \"ltr\" or \"rtl\""))
      }
    }
  }
  return findings
}

// MARK: - Source hash

/// Returns the first 8 hex chars of SHA-1(value), used as a compact
/// drift-detection fingerprint.
func shortSourceHash(of value: String) -> String {
  let data = Data(value.utf8)
  var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
  data.withUnsafeBytes { buf in
    _ = CC_SHA1(buf.baseAddress, CC_LONG(buf.count), &digest)
  }
  return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
}

/// Rewrites `targetURL` so each translatable line carries an
/// `i18n-source-hash:<hex>` annotation matching the current source value.
/// Lines without a corresponding source key, multiline strings, and
/// blank/comment lines are left untouched.
private func updateSourceHashes(
  source: ParsedFile, targetURL: URL
) throws -> Int {
  guard let raw = try? String(contentsOf: targetURL, encoding: .utf8) else { return 0 }
  let originalEndsWithNewline = raw.hasSuffix("\n")
  var lines = raw.components(separatedBy: "\n")
  if originalEndsWithNewline, lines.last == "" { lines.removeLast() }

  var updated = 0
  for (lineIndex, line) in lines.enumerated() {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
    guard let eq = trimmed.firstIndex(of: "=") else { continue }
    let rawKey = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
    let key = unquoteKey(rawKey)
    guard let sourceValue = source.value(for: key) else { continue }
    // Skip multiline strings — too easy to corrupt.
    let rest = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
    if rest.hasPrefix("\"\"\"") { continue }
    let (valuePart, commentPart) = splitValueAndComment(line)
    let valueLiteral = valuePart.trimmingCharacters(in: .whitespaces)
    guard valueLiteral.hasSuffix("\"") else { continue }
    let hash = shortSourceHash(of: sourceValue)
    let newComment = mergeSourceHash(comment: commentPart, hash: hash)
    let trailingValueWhitespace = valuePart.suffix(while: { $0 == " " || $0 == "\t" })
    let valueWithoutTrailing = String(valuePart.dropLast(trailingValueWhitespace.count))
    let rebuilt =
      newComment.isEmpty
      ? valueWithoutTrailing
      : "\(valueWithoutTrailing)  \(newComment)"
    if rebuilt != line {
      lines[lineIndex] = rebuilt
      updated += 1
    }
  }

  var joined = lines.joined(separator: "\n")
  if originalEndsWithNewline { joined.append("\n") }
  try joined.write(to: targetURL, atomically: true, encoding: .utf8)
  return updated
}

/// Merges or replaces an `i18n-source-hash:` directive in the given comment
/// (which may be empty or contain other directives like `i18n-ignore`).
private func mergeSourceHash(comment: String, hash: String) -> String {
  let trimmed = comment.trimmingCharacters(in: .whitespaces)
  if trimmed.isEmpty {
    return "# i18n-source-hash:\(hash)"
  }
  // Strip the leading '#' for tokenization.
  let body =
    trimmed.hasPrefix("#")
    ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    : trimmed
  let pieces = body.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
  var kept: [String] = []
  for piece in pieces {
    if piece.lowercased().hasPrefix("i18n-source-hash:") { continue }
    kept.append(piece)
  }
  kept.append("i18n-source-hash:\(hash)")
  return "# " + kept.joined(separator: " ")
}

extension String {
  fileprivate func suffix(while predicate: (Character) -> Bool) -> Substring {
    var index = endIndex
    while index > startIndex {
      let prev = self.index(before: index)
      if !predicate(self[prev]) { break }
      index = prev
    }
    return self[index..<endIndex]
  }
}

// MARK: - Main

private func main() -> Never {
  let arguments = parseArguments()
  let bundles = discoverBundles(paths: arguments.paths)
  if bundles.isEmpty {
    FileHandle.standardError.write(
      Data("No bundles found. Pass a bundle path or run from a directory with Examples/.\n".utf8))
    exit(2)
  }

  if arguments.updateSourceHashes {
    var totalUpdated = 0
    for bundle in bundles {
      let source = parseTOMLFile(at: bundle.sourceURL)
      for entry in bundle.localeURLs {
        let count = (try? updateSourceHashes(source: source, targetURL: entry.url)) ?? 0
        if count > 0 {
          print("\(bundle.name)/\(entry.code): updated \(count) line(s)")
          totalUpdated += count
        }
      }
    }
    print("Updated \(totalUpdated) line(s) total.")
    exit(0)
  }

  var bundleResults: [(BundleTarget, [LocaleReport], [Finding])] = []
  for bundle in bundles {
    let source = parseTOMLFile(at: bundle.sourceURL)
    let sourceFindings = lintSource(source)
    let localeReports = bundle.localeURLs.map { entry -> LocaleReport in
      let target = parseTOMLFile(at: entry.url)
      return lintLocale(
        source: source, target: target, bundleName: bundle.name, localeCode: entry.code)
    }
    bundleResults.append((bundle, localeReports, sourceFindings))
  }

  let hadError: Bool
  if arguments.json {
    hadError = emitJSON(bundles: bundleResults, strict: arguments.strict)
  } else {
    hadError = printTextReport(bundles: bundleResults, strict: arguments.strict)
  }
  exit(hadError ? 1 : 0)
}

main()
