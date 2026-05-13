import Foundation
import Testing

@testable import GUIForCLICore

@Test func parsesIconMapTomlBySource() throws {
  let iconMap = try BundleIconMap(
    tomlData: Data(
      """
      [sf-symbols]
      "fasta" = "point.3.connected.trianglepath.dotted"

      [windows]
      "download" = "\\uE896"
      "refresh" = " \\uE72C"

      [bootstrap]
      "warning" = "exclamation-triangle-fill"

      [emoji]
      "warning" = "⚠️"
      """.utf8))

  #expect(
    iconMap.resolving("fasta", source: BundleIconMap.sfSymbolsSource)
      == "point.3.connected.trianglepath.dotted")
  #expect(iconMap.resolving("download", source: BundleIconMap.windowsSource) == "\u{E896}")
  #expect(iconMap.resolving("refresh", source: BundleIconMap.windowsSource) == " \u{E72C}")
  #expect(
    iconMap.resolving("warning", source: BundleIconMap.bootstrapSource)
      == "exclamation-triangle-fill")
  #expect(iconMap.resolving("warning", source: BundleIconMap.emojiSource) == "⚠️")
}

@Test func rejectsMalformedIconMapToml() {
  #expect(throws: BundleIconMapError.invalidLine(2, "\"warning\" = \"\\uZZZZ\"")) {
    _ = try BundleIconMap(
      tomlData: Data(
        """
        [emoji]
        "warning" = "\\uZZZZ"
        """.utf8))
  }
}

@Test func bundleLoaderMergesBuiltinAndBundleIconMaps() throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }

  try Data(
    """
    {
      "id": "icon-map-bundle",
      "displayName": "Icon Map Bundle",
      "summary": "Tests bundle icon maps.",
      "iconName": "fasta",
      "pages": [
        {
          "id": "main",
          "title": "Main",
          "summary": "Main page.",
          "sections": [
            {
              "id": "content"
            }
          ]
        }
      ]
    }
    """.utf8
  ).write(to: directory.appendingPathComponent("manifest.json", isDirectory: false))
  try Data(
    """
    [sf-symbols]
    "fasta" = "point.3.connected.trianglepath.dotted"

    [bootstrap]
    "fasta" = "diagram-3"
    """.utf8
  ).write(to: directory.appendingPathComponent("iconmap.toml", isDirectory: false))

  let loaded = try BundleSourceLoader().load(from: directory)

  #expect(
    loaded.iconMap.resolving("fasta", source: BundleIconMap.sfSymbolsSource)
      == "point.3.connected.trianglepath.dotted")
  #expect(loaded.iconMap.resolving("fasta", source: BundleIconMap.bootstrapSource) == "diagram-3")
  #expect(
    loaded.iconMap.resolving("terminal", source: BundleIconMap.bootstrapSource) == "terminal")
}

@Test func demoBundleIconNamesResolveThroughBundleIconMap() throws {
  let loaded = try BundleSourceLoader().load(from: DemoBundle.wgsExtractResourceRootURL)
  let iconNames = Set(iconNames(in: loaded.manifest))

  #expect(iconNames.contains("fasta"))
  #expect(iconNames.contains("library"))
  for source in [
    BundleIconMap.sfSymbolsSource,
    BundleIconMap.windowsSource,
    BundleIconMap.bootstrapSource,
    BundleIconMap.emojiSource,
  ] {
    let missing = iconNames.sorted().filter {
      loaded.iconMap.resolving($0, source: source) == nil
    }
    #expect(missing.isEmpty)
  }
}

private func iconNames(in manifest: CLIBundleManifest) -> [String] {
  var names = [manifest.iconName]
  for page in manifest.pages {
    if let iconName = page.iconName {
      names.append(iconName)
    }
    for section in page.sections {
      if let iconName = section.iconName {
        names.append(iconName)
      }
      names.append(contentsOf: section.actions.compactMap(\.iconName))
      for control in section.controls {
        names.append(contentsOf: control.rowActions.compactMap(\.iconName))
      }
    }
  }
  return names
}
