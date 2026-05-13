import Foundation

extension BundleSourceLoader {
  func loadIconMap(rootURL: URL) throws -> BundleIconMap {
    var iconMap = BuiltinIconMap.load()
    let bundleIconMapURL = rootURL.appendingPathComponent("iconmap.toml", isDirectory: false)
    if fileManager.fileExists(atPath: bundleIconMapURL.path) {
      let bundleIconMap = try BundleIconMap(tomlData: Data(contentsOf: bundleIconMapURL))
      iconMap = iconMap.merging(bundleIconMap)
    }
    return iconMap
  }
}
