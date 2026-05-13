package dev.guiforcli.compose.model

data class BundleManifest(
    val id: String,
    val displayName: String,
    val summary: String,
    val iconName: String = "terminal",
    val iconPath: String? = null,
    val textIcon: String? = null,
    val sidebarIconStyle: String = "automatic",
    val terminalTextDirection: String = "ltr",
    val setup: SetupSpec = SetupSpec(),
    val exitCodeReference: List<ExitCodeReferenceEntry> = emptyList(),
    val pages: List<BundlePage>,
    val defaultLocalizationCode: String = "en",
)

data class BundlePage(
    val id: String,
    val title: String,
    val summary: String,
    val iconName: String? = null,
    val textIcon: String? = null,
    val sidebarGroup: String? = null,
    val sections: List<PageSection> = emptyList(),
)

data class PageSection(
    val id: String,
    val title: String? = null,
    val subtitle: String? = null,
    val iconName: String? = null,
    val textIcon: String? = null,
    val dataSource: DataSourceSpec? = null,
    val controls: List<ControlSpec> = emptyList(),
    val actions: List<ActionSpec> = emptyList(),
)

data class ControlSpec(
    val id: String,
    val label: String,
    val kind: String,
    val value: String? = null,
    val placeholder: String? = null,
    val tooltip: String? = null,
    val options: List<ControlOption> = emptyList(),
    val columns: List<ListColumnSpec> = emptyList(),
    val rows: List<ListRowSpec> = emptyList(),
    val rowTemplate: ListRowSpec? = null,
    val items: List<ListItemSpec> = emptyList(),
    val rowActions: List<ActionSpec> = emptyList(),
    val dataSource: DataSourceSpec? = null,
    val configFile: ConfigFileSpec? = null,
    val settings: List<ConfigSettingSpec> = emptyList(),
)

data class ControlOption(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val selected: Boolean = false,
)

data class ListColumnSpec(
    val id: String,
    val title: String,
)

data class ListRowSpec(
    val id: String? = null,
    val title: String? = null,
    val subtitle: String? = null,
    val status: String? = null,
    val values: Map<String, String> = emptyMap(),
    val tags: List<TagSpec> = emptyList(),
)

data class ListItemSpec(
    val values: Map<String, String> = emptyMap(),
)

data class TagSpec(
    val id: String,
    val title: String,
    val style: String = "secondary",
)

data class ActionSpec(
    val id: String,
    val title: String,
    val command: CommandSpec,
    val tooltip: String? = null,
    val iconName: String? = null,
    val textIcon: String? = null,
    val iconOnly: Boolean = false,
    val role: String = "primary",
    val destructive: Boolean = false,
    val visibleWhen: List<ActionConditionSpec> = emptyList(),
    val disabledWhen: List<ActionConditionSpec> = emptyList(),
    val disabledTooltip: String? = null,
    val precheck: ActionPrecheckSpec? = null,
    val confirm: ActionConfirmationSpec? = null,
)

data class CommandSpec(
    val executable: String,
    val arguments: List<String> = emptyList(),
    val optionalArguments: List<List<String>> = emptyList(),
    val environment: Map<String, String> = emptyMap(),
    val workingDirectory: String? = null,
)

data class ActionConditionSpec(
    val placeholder: String,
    val equals: String? = null,
    val notEquals: String? = null,
    val inValues: List<String> = emptyList(),
    val notInValues: List<String> = emptyList(),
    val exists: Boolean? = null,
    val lessThan: String? = null,
    val lessThanOrEqual: String? = null,
    val greaterThan: String? = null,
    val greaterThanOrEqual: String? = null,
)

data class ActionPrecheckSpec(
    val diskSpaceGB: String? = null,
    val diskSpacePath: String? = null,
    val warningMessage: String? = null,
)

data class ActionConfirmationSpec(
    val title: String,
    val message: String? = null,
    val confirmButtonTitle: String = "Continue",
    val cancelButtonTitle: String = "Cancel",
    val requiredText: String? = null,
    val prompt: String? = null,
)

data class DataSourceSpec(
    val path: String,
    val arguments: List<String> = emptyList(),
    val workingDirectory: String? = null,
    val environment: Map<String, String> = emptyMap(),
)

data class DataSourcePayload(
    val options: List<ControlOption>? = null,
    val rows: List<ListRowSpec>? = null,
    val rowActions: List<ActionSpec>? = null,
    val values: Map<String, String>? = null,
)

data class ConfigFileSpec(
    val path: String,
    val format: String = "toml",
    val bootstrap: ConfigBootstrapSpec? = null,
)

data class ConfigBootstrapSpec(
    val mode: String = "createIfMissing",
    val script: ConfigBootstrapScriptSpec? = null,
)

data class ConfigBootstrapScriptSpec(
    val path: String,
    val arguments: List<String> = emptyList(),
    val environment: Map<String, String> = emptyMap(),
    val workingDirectory: String? = null,
)

data class ConfigSettingSpec(
    val id: String,
    val key: String,
    val label: String,
    val kind: String = "text",
    val value: String? = null,
    val placeholder: String? = null,
    val tooltip: String? = null,
    val options: List<ControlOption> = emptyList(),
)

data class SetupSpec(
    val steps: List<SetupStep> = emptyList(),
)

data class SetupStep(
    val id: String,
    val kind: String,
    val label: String,
    val value: String? = null,
    val optional: Boolean = false,
    val arguments: List<String> = emptyList(),
    val environment: Map<String, String> = emptyMap(),
    val workingDirectory: String? = null,
)

data class ExitCodeReferenceEntry(
    val code: Int,
    val title: String,
    val summary: String,
    val severity: String = "error",
)
