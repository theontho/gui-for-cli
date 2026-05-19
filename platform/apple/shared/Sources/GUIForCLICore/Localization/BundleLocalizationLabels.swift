import Foundation

public struct BundleLocalizationLabels: Equatable, Sendable {
  public var standardOptionsSectionTitle: String
  public var languageSectionTitle: String
  public var languagePickerLabel: String
  public var languageSearchPlaceholder: String
  public var languageSystemDefaultLabel: String
  public var languageAITranslatedLabel: String
  public var iconSetPickerLabel: String
  public var iconSetSwiftSymbolsLabel: String
  public var iconSetBootstrapIconsLabel: String
  public var iconSetEmojiLabel: String
  public var colorThemePickerLabel: String
  public var colorThemeSystemLabel: String
  public var colorThemeLightLabel: String
  public var colorThemeDarkLabel: String
  public var layoutDirection: BundleInterfaceLayoutDirection
  public var terminalMainTabTitle: String
  public var terminalCommandOutputLabel: String
  public var terminalShowOutputLabel: String
  public var terminalHideOutputLabel: String
  public var terminalCopyTextLabel: String
  public var terminalCopiedTextLabel: String
  public var terminalCloseButtonTitle: String
  public var terminalCancelButtonTitle: String
  public var terminalCloseSelectedTabAccessibilityLabel: String
  public var sidebarShowLabel: String
  public var sidebarHideLabel: String
  public var openBundleWorkspaceTitle: String
  public var openBundleWorkspaceTooltip: String
  public var setupTitle: String
  public var setupRunButtonTitle: String
  public var setupRerunButtonTitle: String
  public var setupPromptBodyFormat: String
  public var setupPromptAppNameFallback: String
  public var setupRunningTitle: String
  public var setupNoStepsTitle: String
  public var setupStatusReadyTitle: String
  public var setupStatusOkTitle: String
  public var setupStatusFailedTitle: String
  public var setupToolLabel: String
  public var setupVersionLabel: String
  public var setupStepPendingTitle: String
  public var setupStepRunningTitle: String
  public var setupStepOkTitle: String
  public var setupStepWarningTitle: String
  public var setupStepFailedTitle: String
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
    standardOptionsSectionTitle: String = "Standard Options",
    languageSectionTitle: String = "Interface Language",
    languagePickerLabel: String = "Language",
    languageSearchPlaceholder: String = "Search languages",
    languageSystemDefaultLabel: String = "Use system default",
    languageAITranslatedLabel: String = "AI translated",
    iconSetPickerLabel: String = "Icons",
    iconSetSwiftSymbolsLabel: String = "SF Symbols",
    iconSetBootstrapIconsLabel: String = "Bootstrap Icons",
    iconSetEmojiLabel: String = "Emoji",
    colorThemePickerLabel: String = "Theme",
    colorThemeSystemLabel: String = "System",
    colorThemeLightLabel: String = "Light",
    colorThemeDarkLabel: String = "Dark",
    layoutDirection: BundleInterfaceLayoutDirection = .leftToRight,
    terminalMainTabTitle: String = "Main",
    terminalCommandOutputLabel: String = "Command output",
    terminalShowOutputLabel: String = "Show Command Output",
    terminalHideOutputLabel: String = "Hide Command Output",
    terminalCopyTextLabel: String = "Copy terminal text",
    terminalCopiedTextLabel: String = "Copied!",
    terminalCloseButtonTitle: String = "Close",
    terminalCancelButtonTitle: String = "Cancel",
    terminalCloseSelectedTabAccessibilityLabel: String =
      "Close or cancel selected terminal tab",
    sidebarShowLabel: String = "Show Sidebar",
    sidebarHideLabel: String = "Hide Sidebar",
    openBundleWorkspaceTitle: String = "Open Bundle Workspace",
    openBundleWorkspaceTooltip: String = "Open the writable bundle workspace folder.",
    setupTitle: String = "Setup",
    setupRunButtonTitle: String = "Run Setup",
    setupRerunButtonTitle: String = "Rerun Setup",
    setupPromptBodyFormat: String =
      "Do you want to run setup? %{app} will probably not work properly without running setup.",
    setupPromptAppNameFallback: String = "This app",
    setupRunningTitle: String = "Running setup...",
    setupNoStepsTitle: String = "No setup steps are defined for this bundle.",
    setupStatusReadyTitle: String = "Review and run this bundle's setup steps.",
    setupStatusOkTitle: String = "Setup completed successfully.",
    setupStatusFailedTitle: String = "Setup failed. Review command output for details.",
    setupToolLabel: String = "Tool",
    setupVersionLabel: String = "Version",
    setupStepPendingTitle: String = "Pending",
    setupStepRunningTitle: String = "Running",
    setupStepOkTitle: String = "OK",
    setupStepWarningTitle: String = "Warning",
    setupStepFailedTitle: String = "Failed",
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
    self.standardOptionsSectionTitle = standardOptionsSectionTitle
    self.languageSectionTitle = languageSectionTitle
    self.languagePickerLabel = languagePickerLabel
    self.languageSearchPlaceholder = languageSearchPlaceholder
    self.languageSystemDefaultLabel = languageSystemDefaultLabel
    self.languageAITranslatedLabel = languageAITranslatedLabel
    self.iconSetPickerLabel = iconSetPickerLabel
    self.iconSetSwiftSymbolsLabel = iconSetSwiftSymbolsLabel
    self.iconSetBootstrapIconsLabel = iconSetBootstrapIconsLabel
    self.iconSetEmojiLabel = iconSetEmojiLabel
    self.colorThemePickerLabel = colorThemePickerLabel
    self.colorThemeSystemLabel = colorThemeSystemLabel
    self.colorThemeLightLabel = colorThemeLightLabel
    self.colorThemeDarkLabel = colorThemeDarkLabel
    self.layoutDirection = layoutDirection
    self.terminalMainTabTitle = terminalMainTabTitle
    self.terminalCommandOutputLabel = terminalCommandOutputLabel
    self.terminalShowOutputLabel = terminalShowOutputLabel
    self.terminalHideOutputLabel = terminalHideOutputLabel
    self.terminalCopyTextLabel = terminalCopyTextLabel
    self.terminalCopiedTextLabel = terminalCopiedTextLabel
    self.terminalCloseButtonTitle = terminalCloseButtonTitle
    self.terminalCancelButtonTitle = terminalCancelButtonTitle
    self.terminalCloseSelectedTabAccessibilityLabel =
      terminalCloseSelectedTabAccessibilityLabel
    self.sidebarShowLabel = sidebarShowLabel
    self.sidebarHideLabel = sidebarHideLabel
    self.openBundleWorkspaceTitle = openBundleWorkspaceTitle
    self.openBundleWorkspaceTooltip = openBundleWorkspaceTooltip
    self.setupTitle = setupTitle
    self.setupRunButtonTitle = setupRunButtonTitle
    self.setupRerunButtonTitle = setupRerunButtonTitle
    self.setupPromptBodyFormat = setupPromptBodyFormat
    self.setupPromptAppNameFallback = setupPromptAppNameFallback
    self.setupRunningTitle = setupRunningTitle
    self.setupNoStepsTitle = setupNoStepsTitle
    self.setupStatusReadyTitle = setupStatusReadyTitle
    self.setupStatusOkTitle = setupStatusOkTitle
    self.setupStatusFailedTitle = setupStatusFailedTitle
    self.setupToolLabel = setupToolLabel
    self.setupVersionLabel = setupVersionLabel
    self.setupStepPendingTitle = setupStepPendingTitle
    self.setupStepRunningTitle = setupStepRunningTitle
    self.setupStepOkTitle = setupStepOkTitle
    self.setupStepWarningTitle = setupStepWarningTitle
    self.setupStepFailedTitle = setupStepFailedTitle
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
      standardOptionsSectionTitle: table?["app.standardOptions.title"] ?? "Standard Options",
      languageSectionTitle: table?["language.setting.title"] ?? "Interface Language",
      languagePickerLabel: table?["language.setting.label"] ?? "Language",
      languageSearchPlaceholder: table?["language.setting.searchPlaceholder"]
        ?? "Search languages",
      languageSystemDefaultLabel: table?["language.setting.systemDefault"]
        ?? "Use system default",
      languageAITranslatedLabel: table?["language.setting.aiTranslated"]
        ?? "AI translated",
      iconSetPickerLabel: table?["app.iconSet.label"] ?? "Icons",
      iconSetSwiftSymbolsLabel: table?["app.iconSet.sfSymbols"] ?? "SF Symbols",
      iconSetBootstrapIconsLabel: table?["app.iconSet.bootstrapIcons"] ?? "Bootstrap Icons",
      iconSetEmojiLabel: table?["app.iconSet.emoji"] ?? "Emoji",
      colorThemePickerLabel: table?["app.colorTheme.label"] ?? "Theme",
      colorThemeSystemLabel: table?["app.colorTheme.system"] ?? "System",
      colorThemeLightLabel: table?["app.colorTheme.light"] ?? "Light",
      colorThemeDarkLabel: table?["app.colorTheme.dark"] ?? "Dark",
      layoutDirection: Self.layoutDirection(from: table?["language.layoutDirection"]),
      terminalMainTabTitle: table?["app.terminal.mainTab.title"] ?? "Main",
      terminalCommandOutputLabel: table?["app.terminal.commandOutput.label"] ?? "Command output",
      terminalShowOutputLabel: table?["app.terminal.showOutput.label"]
        ?? "Show Command Output",
      terminalHideOutputLabel: table?["app.terminal.hideOutput.label"]
        ?? "Hide Command Output",
      terminalCopyTextLabel: table?["app.terminal.copyText.label"]
        ?? "Copy terminal text",
      terminalCopiedTextLabel: table?["app.terminal.copiedText.label"] ?? "Copied!",
      terminalCloseButtonTitle: table?["app.terminal.closeButton.title"] ?? "Close",
      terminalCancelButtonTitle: table?["app.terminal.cancelButton.title"] ?? "Cancel",
      terminalCloseSelectedTabAccessibilityLabel: table?[
        "app.terminal.closeSelectedTab.accessibilityLabel"
      ] ?? "Close or cancel selected terminal tab",
      sidebarShowLabel: table?["app.sidebar.show.label"] ?? "Show Sidebar",
      sidebarHideLabel: table?["app.sidebar.hide.label"] ?? "Hide Sidebar",
      openBundleWorkspaceTitle: table?[
        "actions.settings.settings-paths.open-bundle-workspace.title"
      ] ?? "Open Bundle Workspace",
      openBundleWorkspaceTooltip: table?[
        "actions.settings.settings-paths.open-bundle-workspace.tooltip"
      ] ?? "Open the writable bundle workspace folder.",
      setupTitle: table?["app.setup.status.title"] ?? "Setup",
      setupRunButtonTitle: table?["app.setup.runButton.title"] ?? "Run Setup",
      setupRerunButtonTitle: table?["app.setup.rerunButton.title"] ?? "Rerun Setup",
      setupPromptBodyFormat: table?["app.setup.prompt.bodyFormat"]
        ?? "Do you want to run setup? %{app} will probably not work properly without running setup.",
      setupPromptAppNameFallback: table?["app.setup.prompt.appNameFallback"] ?? "This app",
      setupRunningTitle: table?["app.setup.status.running"] ?? "Running setup...",
      setupNoStepsTitle: table?["app.setup.status.none"]
        ?? "No setup steps are defined for this bundle.",
      setupStatusReadyTitle: table?["app.setup.status.ready"]
        ?? "Review and run this bundle's setup steps.",
      setupStatusOkTitle: table?["app.setup.status.ok"] ?? "Setup completed successfully.",
      setupStatusFailedTitle: table?["app.setup.status.failed"]
        ?? "Setup failed. Review command output for details.",
      setupToolLabel: table?["app.setup.tool.label"] ?? "Tool",
      setupVersionLabel: table?["app.setup.version.label"] ?? "Version",
      setupStepPendingTitle: table?["app.setup.step.pending"] ?? "Pending",
      setupStepRunningTitle: table?["app.setup.step.running"] ?? "Running",
      setupStepOkTitle: table?["app.setup.step.ok"] ?? "OK",
      setupStepWarningTitle: table?["app.setup.step.warning"] ?? "Warning",
      setupStepFailedTitle: table?["app.setup.step.failed"] ?? "Failed",
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
  public var isAITranslated: Bool

  public var id: String { code }

  public init(code: String, displayName: String, isAITranslated: Bool = false) {
    self.code = code
    self.displayName = displayName
    self.isAITranslated = isAITranslated
  }
}
