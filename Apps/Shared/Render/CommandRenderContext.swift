import GUIForCLICore
import SwiftUI

struct CommandRenderContext: Sendable {
  var fieldValues: [String: String] = [:]
  var checkedOptions: [String: String] = [:]
  var configValues: [String: String] = [:]
  var rowValues: [String: String] = [:]
  var bundleRootPath: String?

  func value(for placeholder: String) -> String? {
    if placeholder == "bundleRoot" || placeholder == "bundleWorkspace" {
      return bundleRootPath
    }
    if placeholder.hasPrefix("row.") {
      return rowValues[String(placeholder.dropFirst(4))]
    }
    if placeholder.hasPrefix("config.") {
      return configValues[String(placeholder.dropFirst(7))]
    }
    if let computedValue = computedFileStateValue(for: placeholder) {
      return computedValue
    }
    return rowValues[placeholder]
      ?? checkedOptions[placeholder]
      ?? fieldValues[placeholder]
      ?? configValues[placeholder]
  }

  func interpolated(_ value: String) -> String {
    var result = value
    let pattern = #"\{\{([^}]+)\}\}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return result
    }
    let matches = regex.matches(
      in: value,
      range: NSRange(value.startIndex..<value.endIndex, in: value))
    for match in matches.reversed() {
      guard
        let placeholderRange = Range(match.range(at: 1), in: value),
        let replacementRange = Range(match.range(at: 0), in: result)
      else {
        continue
      }
      let placeholder = String(value[placeholderRange]).trimmingCharacters(in: .whitespaces)
      result.replaceSubrange(replacementRange, with: self.value(for: placeholder) ?? "")
    }
    return result
  }

  private func computedFileStateValue(for placeholder: String) -> String? {
    guard
      let separator = placeholder.lastIndex(of: "."),
      placeholder.index(after: separator) < placeholder.endIndex
    else {
      return nil
    }

    let fieldID = String(placeholder[..<separator])
    let property = String(placeholder[placeholder.index(after: separator)...])

    switch property {
    case "pathExtension":
      guard let path = fieldValues[fieldID]?.nonEmpty ?? configValues[fieldID]?.nonEmpty else {
        return ""
      }
      return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        .pathExtension.lowercased()
    case "isIndexed":
      guard let path = fieldValues[fieldID]?.nonEmpty ?? configValues[fieldID]?.nonEmpty else {
        return Self.boolString(false)
      }
      return Self.boolString(Self.isIndexedAlignment(path: path))
    case "isSorted":
      guard let path = fieldValues[fieldID]?.nonEmpty ?? configValues[fieldID]?.nonEmpty else {
        return Self.boolString(false)
      }
      return Self.boolString(Self.isSortedAlignment(path: path))
    case "exists":
      guard let path = fieldValues[fieldID]?.nonEmpty ?? configValues[fieldID]?.nonEmpty else {
        return Self.boolString(false)
      }
      let expanded = (path as NSString).expandingTildeInPath
      return Self.boolString(FileManager.default.fileExists(atPath: expanded))
    case "fileSize":
      guard let bytes = Self.fileByteSize(fieldValues[fieldID] ?? configValues[fieldID]) else {
        return ""
      }
      return String(bytes)
    case "fileSizeGB":
      guard let bytes = Self.fileByteSize(fieldValues[fieldID] ?? configValues[fieldID]) else {
        return ""
      }
      let gb = Double(bytes) / 1_073_741_824.0
      return String(format: "%.2f", gb)
    case "parentDir":
      guard let path = fieldValues[fieldID]?.nonEmpty ?? configValues[fieldID]?.nonEmpty else {
        return ""
      }
      let expanded = (path as NSString).expandingTildeInPath
      return URL(fileURLWithPath: expanded).deletingLastPathComponent().path
    default:
      return nil
    }
  }

  private static func fileByteSize(_ raw: String?) -> Int64? {
    guard let raw = raw?.nonEmpty else { return nil }
    let expanded = (raw as NSString).expandingTildeInPath
    guard
      let attrs = try? FileManager.default.attributesOfItem(atPath: expanded),
      let size = attrs[.size] as? NSNumber
    else {
      return nil
    }
    return size.int64Value
  }

  private static func boolString(_ value: Bool) -> String {
    value ? "true" : "false"
  }

  private static func isIndexedAlignment(path: String) -> Bool {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let indexPaths = [
      "\(url.path).bai",
      "\(url.path).crai",
      "\(url.path).csi",
      url.deletingPathExtension().appendingPathExtension("bai").path,
      url.deletingPathExtension().appendingPathExtension("crai").path,
      url.deletingPathExtension().appendingPathExtension("csi").path,
    ]
    return indexPaths.contains { FileManager.default.fileExists(atPath: $0) }
  }

  private static func isSortedAlignment(path: String) -> Bool {
    if isIndexedAlignment(path: path) {
      return true
    }
    let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
    return filename.contains(".sorted.") || filename.contains("_sorted.")
      || filename.hasSuffix(".sorted.bam") || filename.hasSuffix(".sorted.cram")
      || filename.contains(".sort.") || filename.contains("_sort.")
  }
}
