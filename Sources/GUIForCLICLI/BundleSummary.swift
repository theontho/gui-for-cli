import ArgumentParser
import Foundation
import GUIForCLICore

struct BundleSummary {
  let lines: [String]
  init(loaded: LoadedBundle) {
    var lines: [String] = []
    let manifest = loaded.manifest
    lines.append("\(manifest.displayName) (\(manifest.id))")
    lines.append("  pages: \(manifest.pages.count)")
    for page in manifest.pages {
      let sectionCount = page.sections.count
      let actionCount = page.sections.reduce(0) { $0 + $1.actions.count }
      let controlCount = page.sections.reduce(0) { $0 + $1.controls.count }
      lines.append(
        "    - \(page.id): sections=\(sectionCount) controls=\(controlCount) actions=\(actionCount)"
      )
    }
    if !manifest.exitCodeReference.isEmpty {
      lines.append("  exit-code entries: \(manifest.exitCodeReference.count)")
    }
    if !manifest.setup.steps.isEmpty {
      lines.append("  setup steps: \(manifest.setup.steps.count)")
    }
    lines.append("  locales: \(loaded.localizationOptions.count)")
    self.lines = lines
  }
}

extension String {
  func matchCount(of pattern: String) -> Int {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
    return regex.numberOfMatches(in: self, range: NSRange(startIndex..<endIndex, in: self))
  }
}
