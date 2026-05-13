import Foundation

public struct ConfigFileBootstrapper {
  public var fileManager: FileManager

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  public func bootstrap(
    manifest: CLIBundleManifest,
    rootURL: URL,
    pathOverrides: [String: String] = [:],
    dryRun: Bool = false
  ) throws -> [ConfigBootstrapResult] {
    var results: [ConfigBootstrapResult] = []
    for control in manifest.configEditorControls {
      guard let configFile = control.configFile, let bootstrapSpec = configFile.bootstrap,
        bootstrapSpec.mode != .none
      else {
        continue
      }
      let path = pathOverrides[control.id] ?? configFile.path
      let url = BundlePathResolver.resolveConfigFilePath(path, rootURL: rootURL)
      try results.append(
        bootstrap(
          control: control,
          configFile: configFile,
          mode: bootstrapSpec.mode,
          url: url,
          rootURL: rootURL,
          script: bootstrapSpec.script,
          dryRun: dryRun))
    }
    return results
  }

  private func bootstrap(
    control: ControlSpec,
    configFile: ConfigFileSpec,
    mode: ConfigBootstrapMode,
    url: URL,
    rootURL: URL,
    script: ConfigBootstrapScriptSpec?,
    dryRun: Bool
  ) throws -> ConfigBootstrapResult {
    switch configFile.format {
    case .toml:
      let document = try bootstrapDocument(
        control: control,
        rootURL: rootURL,
        defaultURL: url,
        script: script,
        dryRun: dryRun)
      return try bootstrapToml(
        control: control,
        mode: mode,
        url: document.url,
        contents: document.contents,
        dryRun: dryRun)
    }
  }
}
