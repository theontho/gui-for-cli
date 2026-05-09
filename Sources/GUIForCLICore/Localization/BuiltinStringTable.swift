import Foundation

/// Loads "built-in" runtime localization strings (language metadata, generic
/// app shell labels, and default exit-code descriptions) that ship with the
/// framework rather than each individual bundle.
///
/// Bundle authors only need to localize keys specific to their bundle; the
/// strings provided here are loaded automatically and overlaid beneath any
/// bundle-provided overrides.
public enum BuiltinStringTable {
  public static let defaultLocalizationCode = "en"

  /// Returns the union of locale codes that ship with the framework, ordered
  /// with the default code first followed by the rest in alphabetical order.
  public static func availableLocalizationCodes() -> [String] {
    guard let directoryURL = resourceDirectoryURL() else {
      return [defaultLocalizationCode]
    }
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)) ?? []
    let codes = entries.compactMap { fileName -> String? in
      guard fileName.hasPrefix("strings."), fileName.hasSuffix(".toml") else { return nil }
      let start = fileName.index(fileName.startIndex, offsetBy: "strings.".count)
      let end = fileName.index(fileName.endIndex, offsetBy: -".toml".count)
      guard start < end else { return nil }
      return String(fileName[start..<end])
    }
    var unique = Set(codes)
    unique.insert(defaultLocalizationCode)
    return [defaultLocalizationCode]
      + unique.subtracting([defaultLocalizationCode]).sorted()
  }

  /// Builds a string table for the given locale, falling back to the default
  /// (English) locale for any keys missing from the requested locale.
  public static func load(localizationCode: String) -> BundleStringTable {
    let base = (try? loadTable(code: defaultLocalizationCode)) ?? BundleStringTable()
    if localizationCode == defaultLocalizationCode {
      return base
    }
    guard let overlay = try? loadTable(code: localizationCode) else { return base }
    return base.merging(overlay)
  }

  /// Returns the language-display name advertised by the built-in locale, if
  /// available, else `nil`.
  public static func displayName(for localizationCode: String) -> String? {
    guard let table = try? loadTable(code: localizationCode) else { return nil }
    return table["language.name"]
  }

  private static func loadTable(code: String) throws -> BundleStringTable {
    guard let url = resourceURL(for: code) else {
      throw BundleLocalizationError.invalidLine(0, "Missing built-in strings for \(code)")
    }
    return try BundleStringTable(tomlData: Data(contentsOf: url))
  }

  private static func resourceURL(for code: String) -> URL? {
    Bundle.module.url(
      forResource: "strings.\(code)",
      withExtension: "toml",
      subdirectory: "Resources/BuiltinStrings")
      ?? resourceDirectoryURL()?
      .appendingPathComponent("strings.\(code).toml", isDirectory: false)
  }

  private static func resourceDirectoryURL() -> URL? {
    if let url = Bundle.module.url(
      forResource: "BuiltinStrings", withExtension: nil, subdirectory: "Resources")
    {
      return url
    }
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Resources/BuiltinStrings", isDirectory: true)
    return FileManager.default.fileExists(atPath: sourceURL.path) ? sourceURL : nil
  }
}
