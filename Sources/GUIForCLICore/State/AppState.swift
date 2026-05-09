import Foundation

/// App-global UI state that is not scoped to a single bundle.
///
/// Stored as JSON at `<configDirectory>/app-state.json` so the same settings
/// can be carried with the rest of the user-managed configuration without
/// relying on `UserDefaults`.
public struct AppState: Codable, Equatable, Sendable {
  /// Discrete dynamic-type step for the in-app text scaling controls.
  public var textScaleStep: Int

  public init(textScaleStep: Int = 0) {
    self.textScaleStep = textScaleStep
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    textScaleStep = try container.decodeIfPresent(Int.self, forKey: .textScaleStep) ?? 0
  }

  private enum CodingKeys: String, CodingKey {
    case textScaleStep
  }
}

/// Atomic JSON-backed store for `AppState`.
public struct AppStateStore: @unchecked Sendable {
  public static let fileName = "app-state.json"

  public let fileURL: URL
  public let fileManager: FileManager

  public init(
    configDirectory: URL = AppPaths.configDirectory(),
    fileManager: FileManager = .default
  ) {
    self.fileURL = configDirectory.appendingPathComponent(Self.fileName, isDirectory: false)
    self.fileManager = fileManager
  }

  public init(fileURL: URL, fileManager: FileManager = .default) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  public func load() -> AppState {
    guard fileManager.fileExists(atPath: fileURL.path) else { return AppState() }
    do {
      let data = try Data(contentsOf: fileURL)
      return try JSONDecoder().decode(AppState.self, from: data)
    } catch {
      return AppState()
    }
  }

  public func save(_ state: AppState) throws {
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(state)
    try data.write(to: fileURL, options: .atomic)
  }
}
