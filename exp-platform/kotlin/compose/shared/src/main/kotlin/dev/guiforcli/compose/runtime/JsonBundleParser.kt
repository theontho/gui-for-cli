package dev.guiforcli.compose.runtime

import dev.guiforcli.compose.model.ActionConditionSpec
import dev.guiforcli.compose.model.ActionConfirmationSpec
import dev.guiforcli.compose.model.ActionPrecheckSpec
import dev.guiforcli.compose.model.ActionSpec
import dev.guiforcli.compose.model.BundleManifest
import dev.guiforcli.compose.model.BundlePage
import dev.guiforcli.compose.model.CommandSpec
import dev.guiforcli.compose.model.ConfigBootstrapScriptSpec
import dev.guiforcli.compose.model.ConfigBootstrapSpec
import dev.guiforcli.compose.model.ConfigFileSpec
import dev.guiforcli.compose.model.ConfigSettingSpec
import dev.guiforcli.compose.model.ControlOption
import dev.guiforcli.compose.model.ControlSpec
import dev.guiforcli.compose.model.DataSourcePayload
import dev.guiforcli.compose.model.DataSourceSpec
import dev.guiforcli.compose.model.ExitCodeReferenceEntry
import dev.guiforcli.compose.model.ListColumnSpec
import dev.guiforcli.compose.model.ListItemSpec
import dev.guiforcli.compose.model.ListRowSpec
import dev.guiforcli.compose.model.PageSection
import dev.guiforcli.compose.model.SetupSpec
import dev.guiforcli.compose.model.SetupStep
import dev.guiforcli.compose.model.TagSpec
import org.json.JSONArray
import org.json.JSONObject

fun parseManifest(json: JSONObject): BundleManifest =
    BundleManifest(
        id = json.requiredString("id"),
        displayName = json.requiredString("displayName"),
        summary = json.requiredString("summary"),
        iconName = json.optionalString("iconName") ?: "terminal",
        iconPath = json.optionalString("iconPath"),
        textIcon = json.optionalString("textIcon"),
        sidebarIconStyle = json.optionalString("sidebarIconStyle") ?: "automatic",
        terminalTextDirection = normalizedTextDirection(json.optionalString("terminalTextDirection")),
        setup = json.optionalObject("setup")?.let(::parseSetupSpec) ?: SetupSpec(),
        exitCodeReference = json.optionalArray("exitCodeReference").objects().map(::parseExitCodeReference),
        pages = json.optionalArray("pages").objects().map(::parsePage),
        defaultLocalizationCode = json.optionalString("defaultLocalizationCode") ?: "en",
    )

fun parsePage(json: JSONObject): BundlePage =
    BundlePage(
        id = json.requiredString("id"),
        title = json.requiredString("title"),
        summary = json.requiredString("summary"),
        iconName = json.optionalString("iconName") ?: json.optionalString("systemImage"),
        textIcon = json.optionalString("textIcon"),
        sidebarGroup = json.optionalString("sidebarGroup"),
        sections = json.optionalArray("sections").objects().map(::parseSection),
    )

fun parseDataSourcePayload(json: JSONObject): DataSourcePayload =
    DataSourcePayload(
        options = json.optionalArray("options").objectsOrNull()?.map(::parseControlOption),
        rows = (json.optionalArray("rows") ?: json.optionalArray("items")).objectsOrNull()?.map(::parseListRow),
        rowActions = (json.optionalArray("rowActions") ?: json.optionalArray("actions"))
            .objectsOrNull()
            ?.map(::parseAction),
        values = json.optionalObject("values")?.stringMap(),
    )

private fun parseSection(json: JSONObject): PageSection =
    PageSection(
        id = json.requiredString("id"),
        title = json.optionalString("title"),
        subtitle = json.optionalString("subtitle"),
        iconName = json.optionalString("iconName") ?: json.optionalString("systemImage"),
        textIcon = json.optionalString("textIcon"),
        dataSource = json.optionalObject("dataSource")?.let(::parseDataSource),
        controls = json.optionalArray("controls").objects().map(::parseControl),
        actions = json.optionalArray("actions").objects().map(::parseAction),
    )

private fun parseControl(json: JSONObject): ControlSpec =
    ControlSpec(
        id = json.requiredString("id"),
        label = json.requiredString("label"),
        kind = json.requiredString("kind"),
        value = json.optionalString("value"),
        placeholder = json.optionalString("placeholder"),
        tooltip = json.optionalString("tooltip"),
        options = json.optionalArray("options").objects().map(::parseControlOption),
        columns = json.optionalArray("columns").objects().map(::parseListColumn),
        rows = json.optionalArray("rows").objects().map(::parseListRow),
        rowTemplate = json.optionalObject("rowTemplate")?.let(::parseListRow),
        items = json.optionalArray("items").objects().map(::parseListItem),
        rowActions = json.optionalArray("rowActions").objects().map(::parseAction),
        dataSource = json.optionalObject("dataSource")?.let(::parseDataSource),
        configFile = json.optionalObject("configFile")?.let(::parseConfigFile),
        settings = json.optionalArray("settings").objects().map(::parseConfigSetting),
    )

private fun parseControlOption(json: JSONObject): ControlOption =
    ControlOption(
        id = json.requiredString("id"),
        title = json.requiredString("title"),
        subtitle = json.optionalString("subtitle"),
        selected = json.optBoolean("selected", false),
    )

private fun parseListColumn(json: JSONObject): ListColumnSpec =
    ListColumnSpec(id = json.requiredString("id"), title = json.requiredString("title"))

private fun parseListRow(json: JSONObject): ListRowSpec =
    ListRowSpec(
        id = json.optionalString("id"),
        title = json.optionalString("title"),
        subtitle = json.optionalString("subtitle"),
        status = json.optionalString("status"),
        values = json.optionalObject("values")?.stringMap() ?: emptyMap(),
        tags = json.optionalArray("tags").objects().map(::parseTag),
    )

private fun parseListItem(json: JSONObject): ListItemSpec =
    ListItemSpec(values = json.stringMap())

private fun parseTag(json: JSONObject): TagSpec =
    TagSpec(
        id = json.optionalString("id") ?: json.requiredString("title"),
        title = json.requiredString("title"),
        style = json.optionalString("style") ?: "secondary",
    )

private fun parseAction(json: JSONObject): ActionSpec =
    ActionSpec(
        id = json.requiredString("id"),
        title = json.requiredString("title"),
        tooltip = json.optionalString("tooltip"),
        iconName = json.optionalString("iconName") ?: json.optionalString("systemImage"),
        textIcon = json.optionalString("textIcon"),
        iconOnly = json.optBoolean("iconOnly", false),
        role = json.optionalString("role") ?: "primary",
        destructive = json.optBoolean("destructive", false) || json.optionalString("role") == "destructive",
        visibleWhen = json.optionalArray("visibleWhen").objects().map(::parseCondition),
        disabledWhen = json.optionalArray("disabledWhen").objects().map(::parseCondition),
        disabledTooltip = json.optionalString("disabledTooltip"),
        precheck = json.optionalObject("precheck")?.let(::parsePrecheck),
        confirm = json.optionalObject("confirm")?.let(::parseConfirmation),
        command = json.optionalObject("command")?.let(::parseCommand) ?: CommandSpec(""),
    )

private fun parseCommand(json: JSONObject): CommandSpec =
    CommandSpec(
        executable = json.requiredString("executable"),
        arguments = json.optionalArray("arguments").strings(),
        optionalArguments = json.optionalArray("optionalArguments").arrays().map { it.strings() },
        environment = json.optionalObject("environment")?.stringMap() ?: emptyMap(),
        workingDirectory = json.optionalString("workingDirectory"),
    )

private fun parseCondition(json: JSONObject): ActionConditionSpec =
    ActionConditionSpec(
        placeholder = json.requiredString("placeholder"),
        equals = json.optionalString("equals"),
        notEquals = json.optionalString("notEquals"),
        inValues = json.optionalArray("in").strings(),
        notInValues = json.optionalArray("notIn").strings(),
        exists = if (json.has("exists")) json.optBoolean("exists") else null,
        lessThan = json.optionalString("lessThan"),
        lessThanOrEqual = json.optionalString("lessThanOrEqual"),
        greaterThan = json.optionalString("greaterThan"),
        greaterThanOrEqual = json.optionalString("greaterThanOrEqual"),
    )

private fun parsePrecheck(json: JSONObject): ActionPrecheckSpec =
    ActionPrecheckSpec(
        diskSpaceGB = json.optionalString("diskSpaceGB"),
        diskSpacePath = json.optionalString("diskSpacePath"),
        warningMessage = json.optionalString("warningMessage"),
    )

private fun parseConfirmation(json: JSONObject): ActionConfirmationSpec =
    ActionConfirmationSpec(
        title = json.requiredString("title"),
        message = json.optionalString("message"),
        confirmButtonTitle = json.optionalString("confirmButtonTitle") ?: "Continue",
        cancelButtonTitle = json.optionalString("cancelButtonTitle") ?: "Cancel",
        requiredText = json.optionalString("requiredText"),
        prompt = json.optionalString("prompt"),
    )

private fun parseDataSource(json: JSONObject): DataSourceSpec =
    DataSourceSpec(
        path = json.requiredString("path"),
        arguments = json.optionalArray("arguments").strings(),
        workingDirectory = json.optionalString("workingDirectory"),
        environment = json.optionalObject("environment")?.stringMap() ?: emptyMap(),
    )

private fun parseConfigFile(json: JSONObject): ConfigFileSpec =
    ConfigFileSpec(
        path = json.requiredString("path"),
        format = json.optionalString("format") ?: "toml",
        bootstrap = json.optionalValue("bootstrap")?.let(::parseConfigBootstrap),
    )

private fun parseConfigBootstrap(value: Any): ConfigBootstrapSpec =
    when (value) {
        is Boolean -> ConfigBootstrapSpec(mode = if (value) "createIfMissing" else "none")
        is String -> ConfigBootstrapSpec(mode = value)
        is JSONObject -> ConfigBootstrapSpec(
            mode = value.optionalString("mode") ?: "createIfMissing",
            script = value.optionalObject("script")?.let(::parseConfigBootstrapScript),
        )
        else -> ConfigBootstrapSpec()
    }

private fun parseConfigBootstrapScript(json: JSONObject): ConfigBootstrapScriptSpec =
    ConfigBootstrapScriptSpec(
        path = json.requiredString("path"),
        arguments = json.optionalArray("arguments").strings(),
        environment = json.optionalObject("environment")?.stringMap() ?: emptyMap(),
        workingDirectory = json.optionalString("workingDirectory"),
    )

private fun parseConfigSetting(json: JSONObject): ConfigSettingSpec =
    ConfigSettingSpec(
        id = json.requiredString("id"),
        key = json.optionalString("key") ?: json.requiredString("id"),
        label = json.requiredString("label"),
        kind = json.optionalString("kind") ?: "text",
        value = json.optionalString("value"),
        placeholder = json.optionalString("placeholder"),
        tooltip = json.optionalString("tooltip"),
        options = json.optionalArray("options").objects().map(::parseControlOption),
    )

private fun parseSetupSpec(json: JSONObject): SetupSpec =
    SetupSpec(steps = json.optionalArray("steps").objects().map(::parseSetupStep))

private fun parseSetupStep(json: JSONObject): SetupStep =
    SetupStep(
        id = json.requiredString("id"),
        kind = json.requiredString("kind"),
        label = json.requiredString("label"),
        value = json.optionalString("value"),
        optional = json.optBoolean("optional", false),
        arguments = json.optionalArray("arguments").strings(),
        environment = json.optionalObject("environment")?.stringMap() ?: emptyMap(),
        workingDirectory = json.optionalString("workingDirectory"),
    )

private fun parseExitCodeReference(json: JSONObject): ExitCodeReferenceEntry =
    ExitCodeReferenceEntry(
        code = json.optInt("code"),
        title = json.requiredString("title"),
        summary = json.requiredString("summary"),
        severity = json.optionalString("severity") ?: "error",
    )

private fun normalizedTextDirection(value: String?): String = if (value == "rtl") "rtl" else "ltr"

private fun JSONObject.requiredString(key: String): String = getString(key)
private fun JSONObject.optionalString(key: String): String? =
    if (has(key) && !isNull(key)) optString(key) else null
private fun JSONObject.optionalObject(key: String): JSONObject? =
    if (has(key) && !isNull(key)) optJSONObject(key) else null
private fun JSONObject.optionalArray(key: String): JSONArray? =
    if (has(key) && !isNull(key)) optJSONArray(key) else null
private fun JSONObject.optionalValue(key: String): Any? =
    if (has(key) && !isNull(key)) get(key) else null

private fun JSONArray?.objects(): List<JSONObject> = objectsOrNull() ?: emptyList()
private fun JSONArray?.objectsOrNull(): List<JSONObject>? =
    this?.let { array -> List(array.length()) { array.getJSONObject(it) } }
private fun JSONArray?.strings(): List<String> =
    this?.let { array -> List(array.length()) { array.getString(it) } } ?: emptyList()
private fun JSONArray?.arrays(): List<JSONArray> =
    this?.let { array -> List(array.length()) { array.getJSONArray(it) } } ?: emptyList()
private fun JSONObject.stringMap(): Map<String, String> =
    keys().asSequence().associateWith { key -> optString(key) }
