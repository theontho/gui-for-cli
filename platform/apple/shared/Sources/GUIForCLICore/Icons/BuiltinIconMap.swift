import Foundation

public enum BuiltinIconMap {
  public static func load() -> BundleIconMap {
    for url in resourceURLs() {
      if let data = try? Data(contentsOf: url),
        let map = try? BundleIconMap(tomlData: data)
      {
        return map
      }
    }
    return BundleIconMap()
  }

  private static func resourceURLs() -> [URL] {
    [
      Bundle.module.url(
        forResource: "iconmap",
        withExtension: "toml",
        subdirectory: "Resources/BuiltinIconMap")
    ]
    .compactMap(\.self)
      + resourceDirectoryURLs()
      .map { $0.appendingPathComponent("iconmap.toml", isDirectory: false) }
  }

  private static func resourceDirectoryURLs() -> [URL] {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("resources/BuiltinIconMap", isDirectory: true)
    return [
      Bundle.module.url(
        forResource: "BuiltinIconMap",
        withExtension: nil,
        subdirectory: "Resources"),
      sourceURL,
      Bundle.main.resourceURL?.appendingPathComponent(
        "resources/BuiltinIconMap",
        isDirectory: true),
    ].compactMap(\.self)
  }
}
