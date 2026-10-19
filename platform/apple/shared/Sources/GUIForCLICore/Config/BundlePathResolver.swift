import Foundation

public enum BundlePathResolver {
  public static func resolveConfigFilePath(_ path: String, rootURL: URL) -> URL {
    let expanded = expand(path, rootURL: rootURL)
    let nsPath = expanded as NSString
    if nsPath.isAbsolutePath {
      return URL(fileURLWithPath: expanded, isDirectory: false)
    }
    return rootURL.appendingPathComponent(expanded, isDirectory: false)
  }

  /// Expands bundle path tokens (`{{bundleRoot}}`, `{{home}}`,
  /// `{{applicationSupport}}`, ...), a leading `~/`, and `${VAR}` references.
  /// Other placeholders are left for command rendering.
  public static func expand(
    _ path: String,
    rootURL: URL,
    configURL: URL? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String {
    let home = NSHomeDirectory()
    let configHome = environment["XDG_CONFIG_HOME"] ?? "\(home)/.config"
    let applicationSupport =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
      ?? "\(home)/Library/Application Support"
    let tokens = [
      "bundleRoot": rootURL.path,
      "bundleWorkspace": rootURL.path,
      "home": home,
      "configHome": configHome,
      "userConfig": configHome,
      "applicationSupport": applicationSupport,
      "appConfig": applicationSupport,
      "configPath": configURL?.path ?? "",
      "configDir": configURL?.deletingLastPathComponent().path ?? "",
    ]
    let expanded = PlaceholderTemplate.render(path, keepingUnresolved: true) { tokens[$0] }
      .replacingOccurrences(of: "~/", with: "\(home)/", options: [.anchored])
    return expandEnvironmentVariables(expanded, environment: environment)
  }

  private static func expandEnvironmentVariables(
    _ value: String, environment: [String: String]
  ) -> String {
    var output = ""
    var cursor = value.startIndex
    while let open = value[cursor...].range(of: "${") {
      output += value[cursor..<open.lowerBound]
      guard let close = value[open.upperBound...].firstIndex(of: "}") else {
        output += value[open.lowerBound...]
        return output
      }
      let key = String(value[open.upperBound..<close])
      output += environment[key] ?? String(value[open.lowerBound...close])
      cursor = value.index(after: close)
    }
    output += value[cursor...]
    return output
  }
}
