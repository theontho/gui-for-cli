import Foundation

#if os(macOS)

  extension DataSourceRunner {
    static let maxOutputBytes = 1_048_576
    static let maxErrorMessageBytes = 65_536

    static func run(
      dataSource: ScriptDataSourceSpec,
      rootURL: URL,
      context: CommandRenderContext,
      timeout: Duration,
      supervisor: ProcessSupervisor
    ) async throws -> Data {
      let executable = try resolve(
        BundlePlatformScriptResolver.resolve(dataSource.path, rootURL: rootURL).path,
        rootURL: rootURL)
      let command = PlatformProcessCommandResolver.resolve(
        executable: executable.path,
        arguments: dataSource.arguments.map(context.interpolated))
      let workingDirectory =
        try dataSource.workingDirectory.map { try resolve($0, rootURL: rootURL) } ?? rootURL

      let process: SupervisedProcess
      do {
        process = try supervisor.launch(
          ProcessRequest(
            executable: command.executable,
            arguments: command.arguments,
            workingDirectory: workingDirectory,
            environment: environment(for: dataSource, rootURL: rootURL, context: context),
            mergesStandardError: false,
            captureLimit: maxOutputBytes,
            terminationGracePeriod: .seconds(2)))
      } catch {
        throw DataSourceError.launchFailed(
          path: dataSource.path, message: error.localizedDescription)
      }

      switch await process.wait(timeout: timeout) {
      case .cancelled:
        throw CancellationError()
      case .timedOut:
        throw DataSourceError.timedOut(path: dataSource.path, timeout: timeout)
      case .exited(let exit):
        guard exit.termination.isSuccess else {
          throw DataSourceError.scriptFailed(
            path: dataSource.path,
            termination: exit.termination,
            message: failureMessage(stderr: exit.standardError))
        }
        return exit.standardOutput
      }
    }

    private static func environment(
      for dataSource: ScriptDataSourceSpec,
      rootURL: URL,
      context: CommandRenderContext
    ) -> [String: String] {
      var overrides = [
        "GUI_FOR_CLI_BUNDLE_ROOT": rootURL.path,
        "GUI_FOR_CLI_BUNDLE_WORKSPACE": rootURL.path,
        "GUI_FOR_CLI_DATA_SOURCE": "1",
      ]
      for (key, value) in context.fieldValues {
        overrides["GUI_FOR_CLI_FIELD_\(environmentKey(key))"] = value
      }
      for (key, value) in context.configValues {
        overrides["GUI_FOR_CLI_CONFIG_\(environmentKey(key))"] = value
      }
      for (key, value) in dataSource.environment {
        overrides[key] = context.interpolated(value)
      }
      return ProcessEnvironment.commandEnvironment(overrides: overrides)
    }

    private static func failureMessage(stderr: Data) -> String {
      let message =
        String(decoding: stderr.prefix(maxErrorMessageBytes), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        ?? "Script failed without writing stderr."
      return stderr.count > maxErrorMessageBytes ? "\(message)\n(stderr truncated)" : message
    }

    static func resolve(_ path: String, rootURL: URL) throws -> URL {
      let expanded = BundlePathResolver.expand(path, rootURL: rootURL)
      let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
      let unresolved =
        (expanded as NSString).isAbsolutePath
        ? URL(fileURLWithPath: expanded) : rootURL.appendingPathComponent(expanded)
      let candidate = unresolved.standardizedFileURL.resolvingSymlinksInPath()
      guard candidate.path == root.path || candidate.path.hasPrefix("\(root.path)/") else {
        throw DataSourceError.invalidPath(path)
      }
      return candidate
    }
  }

#endif
