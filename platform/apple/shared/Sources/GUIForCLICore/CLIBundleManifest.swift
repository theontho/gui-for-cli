import Foundation

public struct CLIBundleManifest: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var version: String?
  public var displayName: String
  public var summary: String
  public var iconName: String
  public var iconPath: String?
  public var textIcon: String?
  public var sidebarIconStyle: SidebarIconStyle
  public var terminalTextDirection: TerminalTextDirection
  public var setup: BundleSetup
  public var uninstall: BundleSetup
  public var exitCodeReference: [ExitCodeReferenceEntry]
  public var pages: [BundlePage]
  public var pageFiles: [String]
  public var defaultLocalizationCode: String

  public init(
    id: String,
    version: String? = nil,
    displayName: String,
    summary: String,
    iconName: String,
    iconPath: String? = nil,
    textIcon: String? = nil,
    sidebarIconStyle: SidebarIconStyle = .automatic,
    terminalTextDirection: TerminalTextDirection = .leftToRight,
    setup: BundleSetup = BundleSetup(),
    uninstall: BundleSetup = BundleSetup(),
    exitCodeReference: [ExitCodeReferenceEntry] = [],
    pages: [BundlePage],
    pageFiles: [String] = [],
    defaultLocalizationCode: String = "en"
  ) {
    self.id = id
    self.version = version
    self.displayName = displayName
    self.summary = summary
    self.iconName = iconName
    self.iconPath = iconPath
    self.textIcon = textIcon
    self.sidebarIconStyle = sidebarIconStyle
    self.terminalTextDirection = terminalTextDirection
    self.setup = setup
    self.uninstall = uninstall
    self.exitCodeReference = exitCodeReference
    self.pages = pages
    self.pageFiles = pageFiles
    self.defaultLocalizationCode = defaultLocalizationCode
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    version = try container.decodeIfPresent(String.self, forKey: .version)
    displayName = try container.decode(String.self, forKey: .displayName)
    summary = try container.decode(String.self, forKey: .summary)
    iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "terminal"
    iconPath = try container.decodeIfPresent(String.self, forKey: .iconPath)
    textIcon = try container.decodeIfPresent(String.self, forKey: .textIcon)
    sidebarIconStyle =
      try container.decodeIfPresent(SidebarIconStyle.self, forKey: .sidebarIconStyle) ?? .automatic
    terminalTextDirection =
      try container.decodeIfPresent(TerminalTextDirection.self, forKey: .terminalTextDirection)
      ?? .leftToRight
    setup = try container.decodeIfPresent(BundleSetup.self, forKey: .setup) ?? BundleSetup()
    uninstall = try container.decodeIfPresent(BundleSetup.self, forKey: .uninstall) ?? BundleSetup()
    exitCodeReference =
      try container.decodeIfPresent([ExitCodeReferenceEntry].self, forKey: .exitCodeReference) ?? []
    if let inlinePages = try? container.decode([BundlePage].self, forKey: .pages) {
      pages = inlinePages
      pageFiles = []
    } else {
      pages = []
      pageFiles = try container.decodeIfPresent([String].self, forKey: .pages) ?? []
    }
    defaultLocalizationCode =
      try container.decodeIfPresent(String.self, forKey: .defaultLocalizationCode) ?? "en"
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encodeIfPresent(version, forKey: .version)
    try container.encode(displayName, forKey: .displayName)
    try container.encode(summary, forKey: .summary)
    try container.encode(iconName, forKey: .iconName)
    try container.encodeIfPresent(iconPath, forKey: .iconPath)
    try container.encodeIfPresent(textIcon, forKey: .textIcon)
    try container.encode(sidebarIconStyle, forKey: .sidebarIconStyle)
    try container.encode(terminalTextDirection, forKey: .terminalTextDirection)
    try container.encode(setup, forKey: .setup)
    if !uninstall.steps.isEmpty {
      try container.encode(uninstall, forKey: .uninstall)
    }
    if !exitCodeReference.isEmpty {
      try container.encode(exitCodeReference, forKey: .exitCodeReference)
    }
    if pages.isEmpty {
      try container.encode(pageFiles, forKey: .pages)
    } else {
      try container.encode(pages, forKey: .pages)
    }
    if defaultLocalizationCode != "en" {
      try container.encode(defaultLocalizationCode, forKey: .defaultLocalizationCode)
    }
  }

  public func validate() throws {
    try BundleManifestValidator.validate(self)
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case version
    case displayName
    case summary
    case iconName
    case iconPath
    case textIcon
    case sidebarIconStyle
    case terminalTextDirection
    case setup
    case uninstall
    case exitCodeReference
    case pages
    case defaultLocalizationCode
  }
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

public enum TerminalTextDirection: String, CaseIterable, Codable, Equatable, Sendable {
  case leftToRight = "ltr"
  case rightToLeft = "rtl"
}
