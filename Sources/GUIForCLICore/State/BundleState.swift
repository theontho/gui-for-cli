import Foundation

/// Per-bundle UI state persisted alongside the bundle's workspace contents.
///
/// Stored as JSON at `<bundleWorkspace>/state.json` so it travels with the
/// workspace (no global `UserDefaults` plist on macOS / iOS).
public struct BundleState: Codable, Equatable, Sendable {
  /// User-selected localization code. `nil` means "follow the system default";
  /// any non-nil value indicates an explicit pick that survives system locale
  /// changes.
  public var localizationCode: String?

  /// Per-control overrides for `configFile.path` (keyed by control id).
  public var configFilePaths: [String: String]

  /// Persisted field values for stateful, non-config-bound controls.
  public var fieldValues: [String: String]

  /// Persisted checkbox-group selections (sorted for stable diffs).
  public var checkedOptions: [String: [String]]

  /// Last selected page id for this bundle, when still present in the manifest.
  public var selectedPageID: String?

  /// Last completed setup run for this bundle. `nil` means setup has not run yet.
  public var setupRun: BundleSetupRunState?

  /// Preferred icon rendering. `.platform` means SF Symbols in SwiftUI and the
  /// platform web icon font in WebUI.
  public var iconSet: BundleIconSet

  /// Preferred color theme for bundle UI chrome.
  public var colorTheme: BundleColorTheme

  public init(
    localizationCode: String? = nil,
    configFilePaths: [String: String] = [:],
    fieldValues: [String: String] = [:],
    checkedOptions: [String: [String]] = [:],
    selectedPageID: String? = nil,
    setupRun: BundleSetupRunState? = nil,
    iconSet: BundleIconSet = .platform,
    colorTheme: BundleColorTheme = .system
  ) {
    self.localizationCode = localizationCode
    self.configFilePaths = configFilePaths
    self.fieldValues = fieldValues
    self.checkedOptions = checkedOptions
    self.selectedPageID = selectedPageID
    self.setupRun = setupRun
    self.iconSet = iconSet
    self.colorTheme = colorTheme
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    localizationCode = try container.decodeIfPresent(String.self, forKey: .localizationCode)
    configFilePaths =
      try container.decodeIfPresent([String: String].self, forKey: .configFilePaths) ?? [:]
    fieldValues =
      try container.decodeIfPresent([String: String].self, forKey: .fieldValues) ?? [:]
    checkedOptions =
      try container.decodeIfPresent([String: [String]].self, forKey: .checkedOptions) ?? [:]
    selectedPageID = try container.decodeIfPresent(String.self, forKey: .selectedPageID)
    setupRun = try container.decodeIfPresent(BundleSetupRunState.self, forKey: .setupRun)
    iconSet = try container.decodeIfPresent(BundleIconSet.self, forKey: .iconSet) ?? .platform
    colorTheme =
      try container.decodeIfPresent(BundleColorTheme.self, forKey: .colorTheme) ?? .system
  }

  private enum CodingKeys: String, CodingKey {
    case localizationCode
    case configFilePaths
    case fieldValues
    case checkedOptions
    case selectedPageID
    case setupRun
    case iconSet
    case colorTheme
  }
}

public struct BundleSetupRunState: Codable, Equatable, Sendable {
  public var status: String
  public var results: [BundleSetupStepRunState]
  public var completedAt: String?
  public var error: String?

  public init(
    status: String,
    results: [BundleSetupStepRunState] = [],
    completedAt: String? = nil,
    error: String? = nil
  ) {
    self.status = status
    self.results = results
    self.completedAt = completedAt
    self.error = error
  }
}

public struct BundleSetupStepRunState: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var label: String
  public var kind: String
  public var command: String?
  public var status: String
  public var exitCode: Int32?

  public init(
    id: String,
    label: String,
    kind: String,
    command: String? = nil,
    status: String,
    exitCode: Int32? = nil
  ) {
    self.id = id
    self.label = label
    self.kind = kind
    self.command = command
    self.status = status
    self.exitCode = exitCode
  }
}

public enum BundleIconSet: String, Codable, Equatable, Hashable, Sendable {
  case platform
  case emoji
}

public enum BundleColorTheme: String, Codable, Equatable, Hashable, Sendable {
  case system
  case light
  case dark
}

/// Atomic JSON-backed store for `BundleState`.
public struct BundleStateStore: @unchecked Sendable {
  public static let fileName = "state.json"

  public let fileURL: URL
  public let fileManager: FileManager

  public init(workspaceURL: URL, fileManager: FileManager = .default) {
    self.fileURL = workspaceURL.appendingPathComponent(Self.fileName, isDirectory: false)
    self.fileManager = fileManager
  }

  /// Loads state from disk. Returns an empty `BundleState` when the file does
  /// not yet exist or is unreadable.
  public func load() -> BundleState {
    guard fileManager.fileExists(atPath: fileURL.path) else { return BundleState() }
    do {
      let data = try Data(contentsOf: fileURL)
      return try JSONDecoder().decode(BundleState.self, from: data)
    } catch {
      return BundleState()
    }
  }

  /// Atomically writes the encoded state to disk, creating intermediate
  /// directories as needed.
  public func save(_ state: BundleState) throws {
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(state)
    try data.write(to: fileURL, options: .atomic)
  }
}
