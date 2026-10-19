import Foundation

public enum DataSourceRunner {
  /// Identifies a data source invocation by the inputs it references, so a page
  /// only reloads a data source when one of its own placeholders changes.
  public static func signature(
    dataSource: ScriptDataSourceSpec,
    rootURL: URL?,
    context: CommandRenderContext
  ) -> String {
    let templates =
      [dataSource.path, dataSource.workingDirectory ?? ""] + dataSource.arguments
      + dataSource.environment.keys.sorted().compactMap { dataSource.environment[$0] }
    let placeholders = Set(templates.flatMap(PlaceholderTemplate.placeholders(in:))).sorted()
    let resolvedPlaceholders = placeholders.map { "\($0)=\(context.value(for: $0) ?? "")" }
    let environmentPairs = dataSource.environment.sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
    return [
      dataSource.path,
      dataSource.arguments.joined(separator: "\u{1f}"),
      environmentPairs.joined(separator: "\u{1e}"),
      dataSource.workingDirectory ?? "",
      rootURL?.path ?? "",
      resolvedPlaceholders.joined(separator: "\u{1d}"),
    ].joined(separator: "\u{1a}")
  }

  /// Runs the data source script and decodes its JSON payload. The script's
  /// process tree is terminated when the calling task is cancelled or `timeout`
  /// elapses.
  public static func load(
    dataSource: ScriptDataSourceSpec,
    rootURL: URL,
    context: CommandRenderContext,
    timeout: Duration = .seconds(15),
    supervisor: ProcessSupervisor = .shared
  ) async throws -> DataSourcePayload {
    #if os(macOS)
      let output = try await run(
        dataSource: dataSource,
        rootURL: rootURL,
        context: context,
        timeout: timeout,
        supervisor: supervisor)
      do {
        return try JSONDecoder().decode(DataSourcePayload.self, from: output)
      } catch {
        throw DataSourceError.invalidJSON(
          path: dataSource.path,
          message: error.localizedDescription,
          preview: outputPreview(output))
      }
    #else
      throw DataSourceError.unsupportedPlatform
    #endif
  }

  public static func outputPreview(_ data: Data) -> String {
    var preview = Data(data.prefix(512))
    var text: String?
    while !preview.isEmpty, text == nil {
      text = String(data: preview, encoding: .utf8)
      if text == nil {
        preview.removeLast()
      }
    }
    if data.count > 512 {
      return "\(text ?? "<non-UTF-8 output>")\n(output truncated)"
    }
    return text ?? "<non-UTF-8 output>"
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
