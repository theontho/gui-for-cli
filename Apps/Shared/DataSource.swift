import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct DynamicControlData: Equatable {
  var options: [ControlOption]?
  var rows: [ListRowSpec]?
  var rowActions: [ActionSpec]?

  init(options: [ControlOption]? = nil, rows: [ListRowSpec]? = nil, rowActions: [ActionSpec]? = nil)
  {
    self.options = options
    self.rows = rows
    self.rowActions = rowActions
  }

  init(payload: DataSourcePayload) {
    self.options = payload.options
    self.rows = payload.rows
    self.rowActions = payload.rowActions
  }
}

struct DataSourcePayload: Decodable, Equatable, Sendable {
  var options: [ControlOption]?
  var rows: [ListRowSpec]?
  var rowActions: [ActionSpec]?
  var values: [String: String]?

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    options = try container.decodeIfPresent([ControlOption].self, forKey: .options)
    rows =
      try container.decodeIfPresent([ListRowSpec].self, forKey: .rows)
      ?? container.decodeIfPresent([ListRowSpec].self, forKey: .items)
    rowActions =
      try container.decodeIfPresent([ActionSpec].self, forKey: .rowActions)
      ?? container.decodeIfPresent([ActionSpec].self, forKey: .actions)
    values = try container.decodeIfPresent([String: String].self, forKey: .values)
  }

  private enum CodingKeys: String, CodingKey {
    case options
    case rows
    case items
    case rowActions
    case actions
    case values
  }
}

enum DataSourceRunner {
  private static let timeoutSeconds: UInt64 = 15
  private static let maxStandardOutputBytes = 1_048_576
  private static let maxStandardErrorBytes = 65_536

  static func signature(
    dataSource: ScriptDataSourceSpec,
    rootURL: URL?,
    context: CommandRenderContext
  ) -> String {
    [
      dataSource.path,
      dataSource.arguments.joined(separator: "\u{1f}"),
      dataSource.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        .joined(separator: "\u{1e}"),
      dataSource.workingDirectory ?? "",
      rootURL?.path ?? "",
      context.fieldValues.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        .joined(separator: "\u{1d}"),
      context.checkedOptions.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        .joined(separator: "\u{1c}"),
      context.configValues.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        .joined(separator: "\u{1b}"),
    ].joined(separator: "\u{1a}")
  }

  static func load(
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

  #if os(macOS)
    private static func run(
      dataSource: ScriptDataSourceSpec,
      rootURL: URL,
      context: CommandRenderContext
    ) async throws -> Data {
      try await withThrowingTaskGroup(of: Data.self) { group in
        group.addTask {
          try await runProcess(dataSource: dataSource, rootURL: rootURL, context: context)
        }
        group.addTask {
          try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
          throw DataSourceError.timedOut(path: dataSource.path, seconds: timeoutSeconds)
        }
        defer { group.cancelAll() }
        guard let output = try await group.next() else {
          throw CancellationError()
        }
        return output
      }
    }

    private static func runProcess(
      dataSource: ScriptDataSourceSpec,
      rootURL: URL,
      context: CommandRenderContext
    ) async throws -> Data {
      let executable = try resolve(dataSource.path, rootURL: rootURL)
      let workingDirectory =
        try dataSource.workingDirectory.map { try resolve($0, rootURL: rootURL) } ?? rootURL
      let processBox = DataSourceProcessBox()

      return try await withTaskCancellationHandler {
        let output = try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Data, Error>) in
          let process = Process()
          process.executableURL = executable
          process.arguments = dataSource.arguments.map { interpolate($0, context: context) }
          process.currentDirectoryURL = workingDirectory

          var environment = ProcessInfo.processInfo.environment
          environment["GUI_FOR_CLI_BUNDLE_ROOT"] = rootURL.path
          environment["GUI_FOR_CLI_BUNDLE_WORKSPACE"] = rootURL.path
          environment["GUI_FOR_CLI_DATA_SOURCE"] = "1"
          for (key, value) in context.fieldValues {
            environment["GUI_FOR_CLI_FIELD_\(environmentKey(key))"] = value
          }
          for (key, value) in context.configValues {
            environment["GUI_FOR_CLI_CONFIG_\(environmentKey(key))"] = value
          }
          for (key, value) in dataSource.environment {
            environment[key] = interpolate(value, context: context)
          }
          process.environment = environment

          let stdout = Pipe()
          let stderr = Pipe()
          let stdoutBuffer = DataSourceOutputBuffer(maxBytes: maxStandardOutputBytes)
          let stderrBuffer = DataSourceOutputBuffer(maxBytes: maxStandardErrorBytes)
          process.standardOutput = stdout
          process.standardError = stderr

          stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
          }
          stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
          }

          process.terminationHandler = { finishedProcess in
            stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
            stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            processBox.clear(finishedProcess)

            if processBox.wasCancelled {
              continuation.resume(throwing: CancellationError())
              return
            }

            let output = stdoutBuffer.snapshot()
            let errorOutput = stderrBuffer.snapshot()
            guard finishedProcess.terminationStatus == 0 else {
              continuation.resume(
                throwing: DataSourceError.scriptFailed(
                  path: dataSource.path,
                  exitCode: finishedProcess.terminationStatus,
                  message: failureMessage(
                    stderr: errorOutput.data,
                    stderrTruncated: errorOutput.truncated)))
              return
            }
            continuation.resume(returning: output.data)
          }

          processBox.set(process)
          do {
            try process.run()
          } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            processBox.clear(process)
            continuation.resume(
              throwing: DataSourceError.launchFailed(
                path: dataSource.path,
                message: error.localizedDescription))
          }
        }
        if Task.isCancelled {
          throw CancellationError()
        }
        return output
      } onCancel: {
        processBox.terminate()
      }
    }

    private static func failureMessage(stderr: Data, stderrTruncated: Bool) -> String {
      let message =
        String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        .nonEmpty
        ?? "Script failed without writing stderr."
      return stderrTruncated ? "\(message)\n(stderr truncated)" : message
    }
  #endif

  private static func outputPreview(_ data: Data) -> String {
    let text = String(data: data.prefix(512), encoding: .utf8) ?? "<non-UTF-8 output>"
    if data.count > 512 {
      return "\(text)\n(output truncated)"
    }
    return text
  }

  #if os(macOS)
    private final class DataSourceProcessBox: @unchecked Sendable {
      private let lock = NSLock()
      private var process: Process?
      private var cancelled = false

      var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
      }

      func set(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = cancelled
        lock.unlock()
        if shouldTerminate {
          process.terminate()
        }
      }

      func clear(_ process: Process) {
        lock.lock()
        if self.process === process {
          self.process = nil
        }
        lock.unlock()
      }

      func terminate() {
        lock.lock()
        cancelled = true
        let process = process
        lock.unlock()
        process?.terminate()
      }
    }

    private final class DataSourceOutputBuffer: @unchecked Sendable {
      private let maxBytes: Int
      private let lock = NSLock()
      private var data = Data()
      private var truncated = false

      init(maxBytes: Int) {
        self.maxBytes = maxBytes
      }

      func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        let remaining = maxBytes - data.count
        if remaining > 0 {
          data.append(contentsOf: chunk.prefix(remaining))
        }
        if chunk.count > max(remaining, 0) {
          truncated = true
        }
        lock.unlock()
      }

      func snapshot() -> (data: Data, truncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, truncated)
      }
    }
  #endif

  #if os(macOS)
    private static func resolve(_ path: String, rootURL: URL) throws -> URL {
      let expanded = BundlePathResolver.expand(path, rootURL: rootURL)
      guard !(expanded as NSString).isAbsolutePath else {
        throw DataSourceError.invalidPath(path)
      }
      let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
      let candidate =
        rootURL
        .appendingPathComponent(expanded)
        .standardizedFileURL
        .resolvingSymlinksInPath()
      guard isContained(candidate, in: root) else {
        throw DataSourceError.invalidPath(path)
      }
      return candidate
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
      let rootPath = root.path
      let candidatePath = candidate.path
      return candidatePath == rootPath || candidatePath.hasPrefix("\(rootPath)/")
    }
  #else
    private static func resolve(_ path: String, rootURL: URL) throws -> URL {
      let expanded = BundlePathResolver.expand(path, rootURL: rootURL)
      if (expanded as NSString).isAbsolutePath {
        return URL(fileURLWithPath: expanded)
      }
      return rootURL.appendingPathComponent(expanded)
    }
  #endif

  private static func interpolate(_ value: String, context: CommandRenderContext) -> String {
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

  private static func environmentKey(_ value: String) -> String {
    value.map { character in
      if character.isLetter || character.isNumber {
        return String(character).uppercased()
      }
      return "_"
    }.joined()
  }
}

enum DataSourceError: LocalizedError, Sendable {
  case scriptFailed(path: String, exitCode: Int32, message: String)
  case launchFailed(path: String, message: String)
  case invalidJSON(path: String, message: String, preview: String)
  case invalidPath(String)
  case timedOut(path: String, seconds: UInt64)
  case unsupportedPlatform

  var errorDescription: String? {
    switch self {
    case .scriptFailed(let path, let exitCode, let message):
      return "\(path) exited with code \(exitCode): \(message)"
    case .launchFailed(let path, let message):
      return "Could not launch \(path): \(message)"
    case .invalidJSON(let path, let message, let preview):
      return "Could not decode JSON from \(path): \(message). Output: \(preview)"
    case .invalidPath(let path):
      return "Data source path must stay inside the bundle: \(path)"
    case .timedOut(let path, let seconds):
      return "\(path) did not finish within \(seconds) seconds."
    case .unsupportedPlatform:
      return "Script-backed data sources are only available on macOS."
    }
  }
}

extension ControlSpec {
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
