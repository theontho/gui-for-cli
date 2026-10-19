import Foundation
import GUIForCLICore
import Testing

@MainActor
@Suite struct BundleConfigStoreTests {
  let root: URL
  let workspaceURL: URL
  let control = ControlSpec(id: "name", label: "Name", kind: .text)
  let session: BundleSession

  init() throws {
    root = try makeTemporaryDirectory()
    let bundleID = "app-config-store-tests-\(UUID().uuidString)"
    workspaceURL = AppPaths.bundleWorkspaceDirectory(for: bundleID)
    let manifest = CLIBundleManifest(
      id: bundleID,
      displayName: "Config Store Tests",
      summary: "Debounced persistence.",
      iconName: "terminal",
      pages: [
        BundlePage(
          id: "main", title: "Main", summary: "Main",
          sections: [PageSection(id: "inputs", title: "Inputs", controls: [control])])
      ])
    try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
    session = BundleSessionLoader.bootstrap(
      sourceRootURL: root,
      fallbackManifest: manifest,
      systemPreferences: [],
      prepareWorkspace: false,
      bootstrapConfig: false,
      loadInitialConfigValues: false)
  }

  private func cleanUp() {
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.removeItem(at: workspaceURL)
  }

  private var savedName: String? {
    (try? session.bundleStateStore.load())?.fieldValues["name"]
  }

  @Test func typingDefersTheStateWriteUntilInputPauses() async throws {
    defer { cleanUp() }
    let store = BundleConfigStore(session: session, persistenceDelay: .milliseconds(200)) { _ in }

    for value in ["A", "Ad", "Ada"] {
      store.fieldValueChanged(value, for: control)
    }

    #expect(store.fieldValues["name"] == "Ada")
    #expect(!FileManager.default.fileExists(atPath: session.bundleStateStore.fileURL.path))
    #expect(try await eventually { savedName == "Ada" })
  }

  @Test func flushWritesPendingStateImmediately() throws {
    defer { cleanUp() }
    let store = BundleConfigStore(session: session, persistenceDelay: .seconds(60)) { _ in }

    store.fieldValueChanged("Grace", for: control)
    store.flushPendingWrites()

    #expect(savedName == "Grace")
  }
}
