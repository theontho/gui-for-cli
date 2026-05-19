import Foundation

#if os(macOS)

  extension DataSourceRunner {
    static let timeoutSeconds: UInt64 = 15
    static let maxStandardOutputBytes = 1_048_576
    static let maxStandardErrorBytes = 65_536

    static func run(
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
      let executable = try resolve(
        BundlePlatformScriptResolver.resolve(dataSource.path, rootURL: rootURL).path,
        rootURL: rootURL)
      let command = PlatformProcessCommandResolver.resolve(
        executable: executable.path,
        arguments: dataSource.arguments.map { interpolate($0, context: context) })
      let workingDirectory =
        try dataSource.workingDirectory.map { try resolve($0, rootURL: rootURL) } ?? rootURL
      let processBox = DataSourceProcessBox()

      return try await withTaskCancellationHandler {
        let output = try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Data, Error>) in
          let process = Process()
          process.executableURL = URL(fileURLWithPath: command.executable)
          process.arguments = command.arguments
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

    static func resolve(_ path: String, rootURL: URL) throws -> URL {
      let expanded = BundlePathResolver.expand(path, rootURL: rootURL)
      if (expanded as NSString).isAbsolutePath {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = URL(fileURLWithPath: expanded)
          .standardizedFileURL
          .resolvingSymlinksInPath()
        guard isContained(candidate, in: root) else {
          throw DataSourceError.invalidPath(path)
        }
        return candidate
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
  }

  final class DataSourceProcessBox: @unchecked Sendable {
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

  final class DataSourceOutputBuffer: @unchecked Sendable {
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
