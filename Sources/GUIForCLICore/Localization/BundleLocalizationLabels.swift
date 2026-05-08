import Foundation

public struct BundleLocalizationLabels: Equatable, Sendable {
  public var languageSectionTitle: String
  public var languagePickerLabel: String
  public var languageSearchPlaceholder: String
  public var languageSystemDefaultLabel: String
  public var layoutDirection: BundleInterfaceLayoutDirection
  public var terminalMainTabTitle: String
  public var terminalCommandOutputLabel: String
  public var terminalShowOutputLabel: String
  public var terminalHideOutputLabel: String
  public var chooseButtonTitle: String
  public var pathPickerErrorTitle: String
  public var settingsFileLabel: String
  public var loadButtonTitle: String
  public var actionsColumnTitle: String
  public var loadingTitle: String
  public var refreshingTitle: String
  public var retryButtonTitle: String
  public var actionPrecheckDiskSpaceTitle: String
  public var actionPrecheckDiskSpaceMessageFormat: String
  public var actionPrecheckDiskSpaceInfoTitle: String
  public var actionPrecheckDiskSpaceInfoFormat: String
  public var libraryStatusLabels: [String: String]
  public var libraryTagLabels: [String: String]

  public init(
    languageSectionTitle: String = "Interface Language",
    languagePickerLabel: String = "Language",
    languageSearchPlaceholder: String = "Search languages",
    languageSystemDefaultLabel: String = "Use system default",
    layoutDirection: BundleInterfaceLayoutDirection = .leftToRight,
    terminalMainTabTitle: String = "Main",
    terminalCommandOutputLabel: String = "Command output",
    terminalShowOutputLabel: String = "Show Command Output",
    terminalHideOutputLabel: String = "Hide Command Output",
    chooseButtonTitle: String = "Choose...",
    pathPickerErrorTitle: String = "Could not choose path",
    settingsFileLabel: String = "Settings File",
    loadButtonTitle: String = "Load",
    actionsColumnTitle: String = "Actions",
    loadingTitle: String = "Loading...",
    refreshingTitle: String = "Refreshing...",
    retryButtonTitle: String = "Retry",
    actionPrecheckDiskSpaceTitle: String = "Not enough free disk space",
    actionPrecheckDiskSpaceMessageFormat: String =
      "Need %{required} GB free at %{path}, only %{available} GB available.",
    actionPrecheckDiskSpaceInfoTitle: String = "Disk space estimate",
    actionPrecheckDiskSpaceInfoFormat: String =
      "Estimated %{required} GB needed at %{path} (%{available} GB free).",
    libraryStatusLabels: [String: String] = [
      "installed": "installed",
      "unindexed": "unindexed",
      "incomplete": "incomplete",
      "missing": "missing",
    ],
    libraryTagLabels: [String: String] = [
      "recommended": "Recommended"
    ]
  ) {
    self.languageSectionTitle = languageSectionTitle
    self.languagePickerLabel = languagePickerLabel
    self.languageSearchPlaceholder = languageSearchPlaceholder
    self.languageSystemDefaultLabel = languageSystemDefaultLabel
    self.layoutDirection = layoutDirection
    self.terminalMainTabTitle = terminalMainTabTitle
    self.terminalCommandOutputLabel = terminalCommandOutputLabel
    self.terminalShowOutputLabel = terminalShowOutputLabel
    self.terminalHideOutputLabel = terminalHideOutputLabel
    self.chooseButtonTitle = chooseButtonTitle
    self.pathPickerErrorTitle = pathPickerErrorTitle
    self.settingsFileLabel = settingsFileLabel
    self.loadButtonTitle = loadButtonTitle
    self.actionsColumnTitle = actionsColumnTitle
    self.loadingTitle = loadingTitle
    self.refreshingTitle = refreshingTitle
    self.retryButtonTitle = retryButtonTitle
    self.actionPrecheckDiskSpaceTitle = actionPrecheckDiskSpaceTitle
    self.actionPrecheckDiskSpaceMessageFormat = actionPrecheckDiskSpaceMessageFormat
    self.actionPrecheckDiskSpaceInfoTitle = actionPrecheckDiskSpaceInfoTitle
    self.actionPrecheckDiskSpaceInfoFormat = actionPrecheckDiskSpaceInfoFormat
    self.libraryStatusLabels = libraryStatusLabels
    self.libraryTagLabels = libraryTagLabels
  }

  public init(table: BundleStringTable?) {
    self.init(
      languageSectionTitle: table?["language.setting.title"] ?? "Interface Language",
      languagePickerLabel: table?["language.setting.label"] ?? "Language",
      languageSearchPlaceholder: table?["language.setting.searchPlaceholder"]
        ?? "Search languages",
      languageSystemDefaultLabel: table?["language.setting.systemDefault"]
        ?? "Use system default",
      layoutDirection: Self.layoutDirection(from: table?["language.layoutDirection"]),
      terminalMainTabTitle: table?["app.terminal.mainTab.title"] ?? "Main",
      terminalCommandOutputLabel: table?["app.terminal.commandOutput.label"] ?? "Command output",
      terminalShowOutputLabel: table?["app.terminal.showOutput.label"]
        ?? "Show Command Output",
      terminalHideOutputLabel: table?["app.terminal.hideOutput.label"]
        ?? "Hide Command Output",
      chooseButtonTitle: table?["app.pathPicker.chooseButton.title"] ?? "Choose...",
      pathPickerErrorTitle: table?["app.pathPicker.error.title"] ?? "Could not choose path",
      settingsFileLabel: table?["app.settingsFile.label"] ?? "Settings File",
      loadButtonTitle: table?["app.loadButton.title"] ?? "Load",
      actionsColumnTitle: table?["app.actionsColumn.title"] ?? "Actions",
      loadingTitle: table?["app.loading.title"] ?? "Loading...",
      refreshingTitle: table?["app.refreshing.title"] ?? "Refreshing...",
      retryButtonTitle: table?["app.retryButton.title"] ?? "Retry",
      actionPrecheckDiskSpaceTitle: table?["app.action.precheck.diskSpace.title"]
        ?? "Not enough free disk space",
      actionPrecheckDiskSpaceMessageFormat: table?["app.action.precheck.diskSpace.messageFormat"]
        ?? "Need %{required} GB free at %{path}, only %{available} GB available.",
      actionPrecheckDiskSpaceInfoTitle: table?["app.action.precheck.diskSpace.infoTitle"]
        ?? "Disk space estimate",
      actionPrecheckDiskSpaceInfoFormat: table?["app.action.precheck.diskSpace.infoFormat"]
        ?? "Estimated %{required} GB needed at %{path} (%{available} GB free).",
      libraryStatusLabels: [
        "installed": table?["library.status.installed"] ?? "installed",
        "unindexed": table?["library.status.unindexed"] ?? "unindexed",
        "incomplete": table?["library.status.incomplete"] ?? "incomplete",
        "missing": table?["library.status.missing"] ?? "missing",
      ],
      libraryTagLabels: [
        "recommended": table?["library.tags.recommended"] ?? "Recommended"
      ])
  }

  private static func layoutDirection(from value: String?) -> BundleInterfaceLayoutDirection {
    switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "rtl", "right-to-left", "righttoleft":
      return .rightToLeft
    default:
      return .leftToRight
    }
  }
}

public enum BundleInterfaceLayoutDirection: String, Equatable, Sendable {
  case leftToRight = "ltr"
  case rightToLeft = "rtl"
}

public struct BundleLocalizationOption: Equatable, Identifiable, Sendable {
  public var code: String
  public var displayName: String

  public var id: String { code }

  public init(code: String, displayName: String) {
    self.code = code
    self.displayName = displayName
  }
}
