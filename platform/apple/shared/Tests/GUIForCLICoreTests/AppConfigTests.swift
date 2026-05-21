import Foundation
import Testing

@testable import GUIForCLICore

@Test func decodesPartialConfigWithDefaults() throws {
  let data = try #"{"logLevel":"debug"}"#.data(using: .utf8).unwrap()
  let config = try JSONDecoder().decode(AppConfig.self, from: data)

  #expect(config.logLevel == .debug)
  #expect((config.dataDirectory as NSString).isAbsolutePath)
  #expect(config.apiKey == nil)
}

@Test func savesAndLoadsConfig() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("gui-for-cli-tests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let configPath = directory.appendingPathComponent("config.json", isDirectory: false)
  let dataDirectory = directory.appendingPathComponent("data", isDirectory: true).path
  let store = AppConfigStore(path: configPath)
  let expected = AppConfig(logLevel: .warning, dataDirectory: dataDirectory, apiKey: "secret")

  try store.save(expected)
  let actual = try store.load()

  #expect(actual == expected)
}

@Test func sampleBundleEncodesAndDecodes() throws {
  let data = try JSONEncoder().encode(DemoBundle.wgsExtract)
  let decoded = try JSONDecoder().decode(CLIBundleManifest.self, from: data)

  #expect(decoded.displayName == "WGS Extract")
  #expect(decoded.version == "0.3.3")
  #expect(decoded.iconPath == "Assets/icon.png")
  #expect(decoded.pages.contains { $0.id == "microarray" })
  #expect(decoded.setup.steps.contains { $0.kind == .setupScript })
  #expect(!decoded.setup.steps.contains { $0.id == "deps-check" })
}

@Test func rejectsRelativeDataDirectory() throws {
  let data = try #"{"dataDirectory":"relative/path"}"#.data(using: .utf8).unwrap()

  #expect(throws: ConfigError.invalidDataDirectory("relative/path")) {
    _ = try JSONDecoder().decode(AppConfig.self, from: data)
  }
}

private enum OptionalUnwrapError: Error {
  case nilValue
}

private extension Optional {
  func unwrap() throws -> Wrapped {
    guard let self else { throw OptionalUnwrapError.nilValue }
    return self
  }
}
