import Foundation

public struct CLIBundleManifest: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var displayName: String
  public var summary: String
  public var iconName: String
  public var iconPath: String?
  public var iconEmoji: String?
  public var sidebarIconStyle: SidebarIconStyle
  public var terminalTextDirection: TerminalTextDirection
  public var setup: BundleSetup
  public var exitCodeReference: [ExitCodeReferenceEntry]
  public var pages: [BundlePage]
  public var pageFiles: [String]

  public init(
    id: String,
    displayName: String,
    summary: String,
    iconName: String,
    iconPath: String? = nil,
    iconEmoji: String? = nil,
    sidebarIconStyle: SidebarIconStyle = .automatic,
    terminalTextDirection: TerminalTextDirection = .leftToRight,
    setup: BundleSetup = BundleSetup(),
    exitCodeReference: [ExitCodeReferenceEntry] = [],
    pages: [BundlePage],
    pageFiles: [String] = []
  ) {
    self.id = id
    self.displayName = displayName
    self.summary = summary
    self.iconName = iconName
    self.iconPath = iconPath
    self.iconEmoji = iconEmoji
    self.sidebarIconStyle = sidebarIconStyle
    self.terminalTextDirection = terminalTextDirection
    self.setup = setup
    self.exitCodeReference = exitCodeReference
    self.pages = pages
    self.pageFiles = pageFiles
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    displayName = try container.decode(String.self, forKey: .displayName)
    summary = try container.decode(String.self, forKey: .summary)
    iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "terminal"
    iconPath = try container.decodeIfPresent(String.self, forKey: .iconPath)
    iconEmoji = try container.decodeIfPresent(String.self, forKey: .iconEmoji)
    sidebarIconStyle =
      try container.decodeIfPresent(SidebarIconStyle.self, forKey: .sidebarIconStyle) ?? .automatic
    terminalTextDirection =
      try container.decodeIfPresent(TerminalTextDirection.self, forKey: .terminalTextDirection)
      ?? .leftToRight
    setup = try container.decodeIfPresent(BundleSetup.self, forKey: .setup) ?? BundleSetup()
    exitCodeReference =
      try container.decodeIfPresent([ExitCodeReferenceEntry].self, forKey: .exitCodeReference) ?? []
    if let inlinePages = try? container.decode([BundlePage].self, forKey: .pages) {
      pages = inlinePages
      pageFiles = []
    } else {
      pages = []
      pageFiles = try container.decodeIfPresent([String].self, forKey: .pages) ?? []
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(displayName, forKey: .displayName)
    try container.encode(summary, forKey: .summary)
    try container.encode(iconName, forKey: .iconName)
    try container.encodeIfPresent(iconPath, forKey: .iconPath)
    try container.encodeIfPresent(iconEmoji, forKey: .iconEmoji)
    try container.encode(sidebarIconStyle, forKey: .sidebarIconStyle)
    try container.encode(terminalTextDirection, forKey: .terminalTextDirection)
    try container.encode(setup, forKey: .setup)
    if !exitCodeReference.isEmpty {
      try container.encode(exitCodeReference, forKey: .exitCodeReference)
    }
    if pages.isEmpty {
      try container.encode(pageFiles, forKey: .pages)
    } else {
      try container.encode(pages, forKey: .pages)
    }
  }

  public func validate() throws {
    try BundleManifestValidator.validate(self)
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case displayName
    case summary
    case iconName
    case iconPath
    case iconEmoji
    case sidebarIconStyle
    case terminalTextDirection
    case setup
    case exitCodeReference
    case pages
  }
}

public enum TerminalTextDirection: String, CaseIterable, Codable, Equatable, Sendable {
  case leftToRight = "ltr"
  case rightToLeft = "rtl"
}

public struct ExitCodeReferenceEntry: Codable, Equatable, Sendable {
  public var code: Int32
  public var title: String
  public var summary: String
  public var severity: ExitCodeSeverity

  public init(
    code: Int32,
    title: String,
    summary: String,
    severity: ExitCodeSeverity = .error
  ) {
    self.code = code
    self.title = title
    self.summary = summary
    self.severity = severity
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    code = try container.decode(Int32.self, forKey: .code)
    title = try container.decode(String.self, forKey: .title)
    summary = try container.decode(String.self, forKey: .summary)
    severity = try container.decodeIfPresent(ExitCodeSeverity.self, forKey: .severity) ?? .error
  }

  private enum CodingKeys: String, CodingKey {
    case code
    case title
    case summary
    case severity
  }
}

public enum ExitCodeSeverity: String, Codable, Equatable, Sendable {
  case warning
  case error
}

public extension CLIBundleManifest {
  static let defaultExitCodeReference: [ExitCodeReferenceEntry] = [
    ExitCodeReferenceEntry(
      code: 1,
      title: "General command failure",
      summary: "The command reported a generic failure. Review the output for details."),
    ExitCodeReferenceEntry(
      code: 2,
      title: "Command-line usage error",
      summary:
        "The command arguments were not accepted. Check required inputs, paths, and selected options before running again."
    ),
    ExitCodeReferenceEntry(
      code: 126,
      title: "Command found but not executable",
      summary:
        "The command or script exists but could not be executed. Check file permissions and whether setup completed successfully."
    ),
    ExitCodeReferenceEntry(
      code: 127,
      title: "Command not found",
      summary:
        "The command runner could not find the executable. Run setup for this bundle and verify the runtime workspace exists."
    ),
    ExitCodeReferenceEntry(
      code: 130,
      title: "Command cancelled",
      summary:
        "The command was interrupted by the user. Any partial output or temporary files may need to be cleaned up before retrying.",
      severity: .warning),
  ]

  var effectiveExitCodeReference: [ExitCodeReferenceEntry] {
    Self.mergedExitCodeReference(overrides: exitCodeReference)
  }

  static func mergedExitCodeReference(
    defaults: [ExitCodeReferenceEntry] = defaultExitCodeReference,
    overrides: [ExitCodeReferenceEntry]
  ) -> [ExitCodeReferenceEntry] {
    var entriesByCode = Dictionary(
      defaults.map { ($0.code, $0) },
      uniquingKeysWith: { first, _ in first })
    for entry in overrides {
      entriesByCode[entry.code] = entry
    }
    return entriesByCode.values.sorted { $0.code < $1.code }
  }
}
