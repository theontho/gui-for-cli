import Foundation

extension ConfigFileBootstrapper {
  func runScript(
    _ script: ConfigBootstrapScriptSpec,
    control: ControlSpec,
    rootURL: URL,
    defaultURL: URL,
    dryRun: Bool
  ) throws -> ScriptBootstrapPayload {
    #if os(macOS) || os(Linux)
      _ = try resolveBundledPath(script.path, rootURL: rootURL, mustExist: false)
      let scriptURL = BundlePlatformScriptResolver.resolve(script.path, rootURL: rootURL)
      guard FileManager.default.fileExists(atPath: scriptURL.path) else {
        throw ConfigBootstrapError.missingScript(scriptURL)
      }
      let workingDirectory = try resolveBundledPath(
        script.workingDirectory ?? "", rootURL: rootURL, mustExist: false)
      let output = Pipe()
      let error = Pipe()
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/sh")
      process.arguments =
        [scriptURL.path]
        + script.arguments.map {
          BundlePathResolver.expand($0, rootURL: rootURL, configURL: defaultURL)
        }
      process.currentDirectoryURL = workingDirectory
      process.standardOutput = output
      process.standardError = error
      process.environment = scriptEnvironment(
        script: script,
        control: control,
        rootURL: rootURL,
        defaultURL: defaultURL,
        dryRun: dryRun)
      let outputBuffer = ScriptBootstrapOutputBuffer()
      let errorBuffer = ScriptBootstrapOutputBuffer()
      output.fileHandleForReading.readabilityHandler = { handle in
        outputBuffer.append(handle.availableData)
      }
      error.fileHandleForReading.readabilityHandler = { handle in
        errorBuffer.append(handle.availableData)
      }
      try process.run()
      process.waitUntilExit()
      output.fileHandleForReading.readabilityHandler = nil
      error.fileHandleForReading.readabilityHandler = nil
      outputBuffer.append(output.fileHandleForReading.readDataToEndOfFile())
      errorBuffer.append(error.fileHandleForReading.readDataToEndOfFile())

      let outputText = String(data: outputBuffer.value(), encoding: .utf8) ?? ""
      let errorText = String(data: errorBuffer.value(), encoding: .utf8) ?? ""
      guard process.terminationStatus == 0 else {
        throw ConfigBootstrapError.scriptFailed(
          scriptURL,
          process.terminationStatus,
          [outputText, errorText].filter { !$0.isEmpty }.joined(separator: "\n"))
      }
      let trimmed = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let data = trimmed.data(using: .utf8),
        let payload = try? JSONDecoder().decode(ScriptBootstrapPayload.self, from: data)
      else {
        throw ConfigBootstrapError.invalidScriptOutput(scriptURL, outputText)
      }
      return payload
    #else
      throw ConfigBootstrapError.unsupportedScriptPlatform
    #endif
  }

  func scriptEnvironment(
    script: ConfigBootstrapScriptSpec,
    control: ControlSpec,
    rootURL: URL,
    defaultURL: URL,
    dryRun: Bool
  ) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment.merge(
      [
        "GUI_FOR_CLI_BUNDLE_ROOT": rootURL.path,
        "GUI_FOR_CLI_BUNDLE_WORKSPACE": rootURL.path,
        "GUI_FOR_CLI_CONFIG_PATH": defaultURL.path,
        "GUI_FOR_CLI_CONFIG_DIR": defaultURL.deletingLastPathComponent().path,
        "GUI_FOR_CLI_CONFIG_CONTROL_ID": control.id,
        "GUI_FOR_CLI_CONFIG_CONTROL_LABEL": control.label,
        "GUI_FOR_CLI_DRY_RUN": dryRun ? "1" : "0",
      ]
    ) { _, new in new }
    environment.merge(
      script.environment.mapValues {
        BundlePathResolver.expand($0, rootURL: rootURL, configURL: defaultURL)
      }
    ) { _, new in new }
    return environment
  }

  func resolveBundledPath(_ path: String, rootURL: URL, mustExist: Bool) throws -> URL {
    guard !path.isEmpty else { return rootURL }
    let nsPath = path as NSString
    guard !nsPath.isAbsolutePath, !path.split(separator: "/").contains("..") else {
      throw ConfigBootstrapError.unsafeScriptPath(path)
    }
    let root = rootURL.standardizedFileURL
    let candidate = root.appendingPathComponent(path).standardizedFileURL
    guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
      throw ConfigBootstrapError.unsafeScriptPath(path)
    }
    if mustExist, !fileManager.fileExists(atPath: candidate.path) {
      throw ConfigBootstrapError.missingScript(candidate)
    }
    return candidate
  }
}

extension CLIBundleManifest {
  public var configEditorControls: [ControlSpec] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
      .filter { $0.kind == .configEditor }
  }
}

private final class ScriptBootstrapOutputBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()

  func append(_ newData: Data) {
    guard !newData.isEmpty else { return }
    lock.lock()
    data.append(newData)
    lock.unlock()
  }

  func value() -> Data {
    lock.lock()
    let output = data
    lock.unlock()
    return output
  }
}
