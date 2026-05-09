import Foundation
import Testing

@testable import GUIForCLICore

@Test func loadsArchiveThroughInjectedExtractor() throws {
  let archive = FileManager.default.temporaryDirectory
    .appendingPathComponent("bundle-\(UUID().uuidString).zip", isDirectory: false)
  try Data("stub".utf8).write(to: archive)
  defer { try? FileManager.default.removeItem(at: archive) }

  let temporaryRoot = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: temporaryRoot) }
  let loader = BundleSourceLoader(
    archiveExtractor: CopyingArchiveExtractor(),
    temporaryRoot: temporaryRoot
  )

  let loaded = try loader.load(from: archive)

  #expect(loaded.manifest.id == "wgs-extract")
  #expect(loaded.isTemporary == true)
}
@Test func writeDemoBundleIncludesSetupScript() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let directory = root.appendingPathComponent("WGSExtract.gui-cli", isDirectory: true)

  try BundleSourceLoader().writeDemoBundle(to: directory, overwrite: false)

  let manifestURL = directory.appendingPathComponent("manifest.json", isDirectory: false)
  let scriptURL = directory.appendingPathComponent(
    "scripts/setup-wgsextract-pixi.sh", isDirectory: false)
  let bootstrapScriptURL = directory.appendingPathComponent(
    "scripts/bootstrap-wgsextract-config.sh", isDirectory: false)
  let runScriptURL = directory.appendingPathComponent(
    "scripts/run-wgsextract.sh", isDirectory: false)
  let dataSourceScriptURL = directory.appendingPathComponent(
    "scripts/list-reference-genomes.sh", isDirectory: false)
  let deleteReferenceScriptURL = directory.appendingPathComponent(
    "scripts/delete-reference-genome.sh", isDirectory: false)
  #expect(FileManager.default.fileExists(atPath: manifestURL.path))
  #expect(
    FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("strings/strings.en.toml", isDirectory: false).path))
  #expect(FileManager.default.fileExists(atPath: scriptURL.path))
  #expect(FileManager.default.fileExists(atPath: bootstrapScriptURL.path))
  #expect(FileManager.default.fileExists(atPath: runScriptURL.path))
  #expect(FileManager.default.fileExists(atPath: dataSourceScriptURL.path))
  #expect(FileManager.default.fileExists(atPath: deleteReferenceScriptURL.path))
  #expect(
    FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Assets/icon.png", isDirectory: false).path))

  let attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
  let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
  #expect(permissions.intValue & 0o111 != 0)
  let bootstrapAttributes = try FileManager.default.attributesOfItem(
    atPath: bootstrapScriptURL.path)
  let bootstrapPermissions = try #require(bootstrapAttributes[.posixPermissions] as? NSNumber)
  #expect(bootstrapPermissions.intValue & 0o111 != 0)
  let runScriptAttributes = try FileManager.default.attributesOfItem(atPath: runScriptURL.path)
  let runScriptPermissions = try #require(runScriptAttributes[.posixPermissions] as? NSNumber)
  #expect(runScriptPermissions.intValue & 0o111 != 0)
  let dataSourceScriptAttributes = try FileManager.default.attributesOfItem(
    atPath: dataSourceScriptURL.path)
  let dataSourceScriptPermissions = try #require(
    dataSourceScriptAttributes[.posixPermissions] as? NSNumber)
  #expect(dataSourceScriptPermissions.intValue & 0o111 != 0)
  let deleteReferenceScriptAttributes = try FileManager.default.attributesOfItem(
    atPath: deleteReferenceScriptURL.path)
  let deleteReferenceScriptPermissions = try #require(
    deleteReferenceScriptAttributes[.posixPermissions] as? NSNumber)
  #expect(deleteReferenceScriptPermissions.intValue & 0o111 != 0)
}

@Test func syncBundleWorkspacePreservesRuntime() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let workspace = root.appendingPathComponent("wgs-extract", isDirectory: true)
  let runtime = workspace.appendingPathComponent("runtime/wgsextract-cli", isDirectory: true)
  try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
  let marker = runtime.appendingPathComponent("installed.txt", isDirectory: false)
  try "keep".write(to: marker, atomically: true, encoding: .utf8)

  try BundleSourceLoader().syncBundleWorkspace(
    from: DemoBundle.wgsExtractResourceRootURL,
    to: workspace)

  #expect(FileManager.default.fileExists(atPath: marker.path))
  #expect(
    FileManager.default.fileExists(
      atPath: workspace.appendingPathComponent("manifest.json", isDirectory: false).path))
  let runScriptURL = workspace.appendingPathComponent(
    "scripts/run-wgsextract.sh", isDirectory: false)
  let runScriptAttributes = try FileManager.default.attributesOfItem(atPath: runScriptURL.path)
  let runScriptPermissions = try #require(runScriptAttributes[.posixPermissions] as? NSNumber)
  #expect(runScriptPermissions.intValue & 0o111 != 0)
}
