import Foundation

public enum DataSourceRunner {
  public static func signature(
    dataSource: ScriptDataSourceSpec,
    rootURL: URL?,
    context: CommandRenderContext
  ) -> String {
    let environmentPairs: [String] = dataSource.environment.sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
    let fieldPairs: [String] = context.fieldValues.sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
    let checkedPairs: [String] = context.checkedOptions.sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
    let configPairs: [String] = context.configValues.sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
    let parts: [String] = [
      dataSource.path,
      dataSource.arguments.joined(separator: "\u{1f}"),
      environmentPairs.joined(separator: "\u{1e}"),
      dataSource.workingDirectory ?? "",
      rootURL?.path ?? "",
      fieldPairs.joined(separator: "\u{1d}"),
      checkedPairs.joined(separator: "\u{1c}"),
      configPairs.joined(separator: "\u{1b}"),
    ]
    return parts.joined(separator: "\u{1a}")
  }

  public static func load(
    dataSource: ScriptDataSourceSpec,
    rootURL: URL,
    context: CommandRenderContext
  ) async throws -> DataSourcePayload {
    #if os(macOS)
      return try await Task.detached {
        let output = try await run(dataSource: dataSource, rootURL: rootURL, context: context)
        do {
          return try JSONDecoder().decode(DataSourcePayload.self, from: output)
        } catch {
          throw DataSourceError.invalidJSON(
            path: dataSource.path,
            message: error.localizedDescription,
            preview: outputPreview(output))
        }
      }.value
    #else
      throw DataSourceError.unsupportedPlatform
    #endif
  }

  public static func outputPreview(_ data: Data) -> String {
    let text = String(data: data.prefix(512), encoding: .utf8) ?? "<non-UTF-8 output>"
    if data.count > 512 {
      return "\(text)\n(output truncated)"
    }
    return text
  }

  public static func interpolate(_ value: String, context: CommandRenderContext) -> String {
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
      result.replaceSubrange(replacementRange, with: context.value(for: placeholder) ?? "")
    }
    return result
  }

  public static func environmentKey(_ value: String) -> String {
    value.map { character in
      if character.isLetter || character.isNumber {
        return String(character).uppercased()
      }
      return "_"
    }.joined()
  }

  #if !os(macOS)
    static func resolve(_ path: String, rootURL: URL) throws -> URL {
      let expanded = BundlePathResolver.expand(path, rootURL: rootURL)
      if (expanded as NSString).isAbsolutePath {
        return URL(fileURLWithPath: expanded)
      }
      return rootURL.appendingPathComponent(expanded)
    }
  #endif
}

public extension ControlSpec {
  func applying(_ dynamicData: DynamicControlData) -> ControlSpec {
    var control = self
    if let options = dynamicData.options {
      control.options = options
    }
    if let rows = dynamicData.rows {
      control.rows = rows
      control.items = []
    }
    if let rowActions = dynamicData.rowActions {
      control.rowActions = rowActions
    }
    return control
  }
}
