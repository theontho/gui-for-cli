import XCTest

@testable import GUIForCLICore

final class StateStoreTests: XCTestCase {
  private var tempDir: URL!

  override func setUpWithError() throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("StateStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testBundleStateStoreRoundTrip() throws {
    let store = BundleStateStore(workspaceURL: tempDir)
    var state = BundleState()
    state.localizationCode = "fr"
    state.configFilePaths["cfg"] = "/tmp/foo"
    state.fieldValues["field"] = "value"
    state.checkedOptions["group"] = ["a", "b"]
    try store.save(state)

    let loaded = store.load()
    XCTAssertEqual(loaded, state)
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
  }

  func testBundleStateStoreMissingFileReturnsEmpty() {
    let store = BundleStateStore(workspaceURL: tempDir)
    XCTAssertEqual(store.load(), BundleState())
  }

  func testBundleStateStoreCorruptFileReturnsEmpty() throws {
    let store = BundleStateStore(workspaceURL: tempDir)
    try "not json".data(using: .utf8)!.write(to: store.fileURL)
    XCTAssertEqual(store.load(), BundleState())
  }

  func testAppStateStoreRoundTrip() throws {
    let fileURL = tempDir.appendingPathComponent("app-state.json")
    let store = AppStateStore(fileURL: fileURL)
    try store.save(AppState(textScaleStep: 4))
    XCTAssertEqual(store.load(), AppState(textScaleStep: 4))
  }

  func testAppStateStoreMissingFileReturnsEmpty() {
    let store = AppStateStore(fileURL: tempDir.appendingPathComponent("missing.json"))
    XCTAssertEqual(store.load(), AppState())
  }
}
