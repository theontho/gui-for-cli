import Foundation
import Testing

@testable import GUIForCLICore

@Suite struct StateStoreTests {
  let directory: URL

  init() throws {
    directory = try temporaryDirectory()
  }

  @Test func bundleStateStoreRoundTrip() throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = BundleStateStore(workspaceURL: directory)
    var state = BundleState()
    state.localizationCode = "fr"
    state.configFilePaths["cfg"] = "/tmp/foo"
    state.fieldValues["field"] = "value"
    state.checkedOptions["group"] = ["a", "b"]
    state.selectedPageID = "settings"
    state.setupRun = BundleSetupRunState(
      status: "failed",
      results: [
        BundleSetupStepRunState(
          id: "pixi", label: "Pixi", kind: "pathTool", command: "/usr/bin/env which pixi",
          status: "ok", exitCode: 0, durationMs: 1200),
        BundleSetupStepRunState(
          id: "deps", label: "Deps", kind: "pixiRun", status: "failed", signal: 9),
      ],
      completedAt: "2026-05-09T18:54:22Z")
    state.iconSet = .emoji
    state.colorTheme = .dark
    state.webUIFont = "sfPro"
    try store.save(state)

    #expect(try store.load() == state)
    #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
  }

  @Test func bundleStateStoreMissingFileReturnsEmpty() throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(try BundleStateStore(workspaceURL: directory).load() == BundleState())
  }

  @Test func bundleStateStoreBacksUpAndReportsCorruptFile() throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = BundleStateStore(workspaceURL: directory)
    try Data("not json".utf8).write(to: store.fileURL)

    let error = try #require(throws: BundleStateLoadError.self) { try store.load() }

    let backupURL = try #require(error.backupURL)
    #expect(backupURL.lastPathComponent.hasPrefix("state.json.corrupt-"))
    #expect(try String(contentsOf: backupURL, encoding: .utf8) == "not json")
    // The next save must not destroy the user's original file.
    try store.save(BundleState())
    #expect(try String(contentsOf: backupURL, encoding: .utf8) == "not json")
  }

  @Test func sessionBootstrapSurfacesCorruptState() throws {
    let bundleID = "state-store-tests-\(UUID().uuidString)"
    let workspaceURL = AppPaths.bundleWorkspaceDirectory(for: bundleID)
    defer { try? FileManager.default.removeItem(at: directory) }
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let manifest = CLIBundleManifest(
      id: bundleID,
      displayName: "State Store Tests",
      summary: "Corrupt state handling.",
      iconName: "terminal",
      pages: [BundlePage(id: "main", title: "Main", summary: "Main", sections: [])])
    try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    try Data("{".utf8).write(to: workspaceURL.appendingPathComponent(BundleStateStore.fileName))

    let session = BundleSessionLoader.bootstrap(
      sourceRootURL: directory,
      fallbackManifest: manifest,
      systemPreferences: [],
      prepareWorkspace: false,
      bootstrapConfig: false,
      loadInitialConfigValues: false)

    #expect(session.bundleState == BundleState())
    #expect(session.startupMessages.contains { $0.hasPrefix("[state:error] Could not read") })
  }

  @Test func appStateStoreRoundTrip() throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStateStore(fileURL: directory.appendingPathComponent("app-state.json"))
    try store.save(AppState(textScaleStep: 4))
    #expect(store.load() == AppState(textScaleStep: 4))
  }

  @Test func appStateStoreMissingFileReturnsEmpty() {
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStateStore(fileURL: directory.appendingPathComponent("missing.json"))
    #expect(store.load() == AppState())
  }
}
