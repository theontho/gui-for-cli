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

  public static func expand(_ path: String, rootURL: URL, configURL: URL? = nil) -> String {
    let home = NSHomeDirectory()
    let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "\(home)/.config"
    let applicationSupport =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
      ?? "\(home)/Library/Application Support"
    let configPath = configURL?.path ?? ""
    let configDir = configURL?.deletingLastPathComponent().path ?? ""

    let expanded =
      path
      .replacingOccurrences(of: "{{bundleRoot}}", with: rootURL.path)
      .replacingOccurrences(of: "{{bundleWorkspace}}", with: rootURL.path)
      .replacingOccurrences(of: "{{home}}", with: home)
      .replacingOccurrences(of: "{{configHome}}", with: configHome)
      .replacingOccurrences(of: "{{userConfig}}", with: configHome)
      .replacingOccurrences(of: "{{applicationSupport}}", with: applicationSupport)
      .replacingOccurrences(of: "{{appConfig}}", with: applicationSupport)
      .replacingOccurrences(of: "{{configPath}}", with: configPath)
      .replacingOccurrences(of: "{{configDir}}", with: configDir)
      .replacingOccurrences(of: "~/", with: "\(home)/", options: [.anchored])
    return expandEnvironmentVariables(expanded)
  }

  private static func expandEnvironmentVariables(_ value: String) -> String {
    var output = ""
    var cursor = value.startIndex
    while let open = value[cursor...].range(of: "${") {
      output += value[cursor..<open.lowerBound]
      guard let close = value[open.upperBound...].firstIndex(of: "}") else {
        output += value[open.lowerBound...]
        return output
      }
      let key = String(value[open.upperBound..<close])
      output += ProcessInfo.processInfo.environment[key] ?? String(value[open.lowerBound...close])
      cursor = value.index(after: close)
    }
    output += value[cursor...]
    return output
  }
}
