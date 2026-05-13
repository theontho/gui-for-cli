package dev.guiforcli.compose.runtime

import dev.guiforcli.compose.model.CommandSpec
import dev.guiforcli.compose.model.ControlSpec
import dev.guiforcli.compose.model.ListItemSpec
import dev.guiforcli.compose.model.ListRowSpec
import java.io.File

data class RenderContext(
    val bundleRootPath: String,
    val homePath: String = System.getProperty("user.home") ?: "/",
    val fieldValues: Map<String, String> = emptyMap(),
    val checkedOptions: Map<String, String> = emptyMap(),
    val configValues: Map<String, String> = emptyMap(),
    val dataValues: Map<String, String> = emptyMap(),
    val rowValues: Map<String, String> = emptyMap(),
)

data class RenderedCommand(
    val executable: String,
    val arguments: List<String>,
    val environment: Map<String, String>,
    val workingDirectory: String?,
) {
    val display: String = listOf(executable, *arguments.toTypedArray()).joinToString(" ") { shellQuote(it) }
}

private val placeholderPattern = Regex("""\Q{{\E([^}]+)\Q}}\E""")

fun renderCommand(command: CommandSpec, context: RenderContext): RenderedCommand {
    val executable = interpolate(command.executable, context)
    val arguments = buildList {
        addAll(command.arguments.map { interpolate(it, context) })
        for (group in command.optionalArguments) {
            val groupHasMissingValue = group.any { value ->
                placeholdersIn(value).any { placeholder -> contextValue(context, placeholder).isNullOrBlank() }
            }
            if (!groupHasMissingValue) {
                addAll(group.map { interpolate(it, context) })
            }
        }
    }
    return RenderedCommand(
        executable = executable,
        arguments = arguments,
        environment = command.environment.mapValues { interpolate(it.value, context) },
        workingDirectory = command.workingDirectory?.let { interpolate(it, context) },
    )
}

fun missingRequiredPlaceholders(command: CommandSpec, context: RenderContext): List<String> =
    placeholdersIn(listOf(command.executable, *command.arguments.toTypedArray()))
        .filter { contextValue(context, it).isNullOrBlank() }

fun interpolate(value: String, context: RenderContext): String =
    placeholderPattern.replace(value) { match ->
        contextValue(context, match.groupValues[1].trim()).orEmpty()
    }

fun contextValue(context: RenderContext, placeholder: String): String? {
    if (placeholder == "bundleRoot" || placeholder == "bundleWorkspace") {
        return context.bundleRootPath
    }
    if (placeholder == "home") {
        return context.homePath
    }
    if (placeholder.startsWith("row.")) {
        return context.rowValues[placeholder.removePrefix("row.")]
    }
    if (placeholder.startsWith("config.")) {
        return context.configValues[placeholder.removePrefix("config.")]
    }
    computedFileStateValue(context, placeholder)?.let { return it }
    return context.dataValues[placeholder]
        ?: context.rowValues[placeholder]
        ?: context.checkedOptions[placeholder]
        ?: context.fieldValues[placeholder]
        ?: context.configValues[placeholder]
}

fun placeholdersIn(values: Iterable<String>): List<String> =
    values.flatMap { value ->
        placeholderPattern.findAll(value).map { it.groupValues[1].trim() }
    }.distinct()

fun placeholdersIn(value: String): List<String> = placeholdersIn(listOf(value))

fun rowContext(baseContext: RenderContext, row: ListRowSpec): RenderContext {
    val values = buildMap {
        putAll(row.values)
        row.id?.let { put("id", it) }
        put("title", row.title ?: row.id.orEmpty())
        row.status?.let { put("status", it) }
    }
    return baseContext.copy(rowValues = values)
}

fun hydrateRows(control: ControlSpec): List<ListRowSpec> {
    if (control.items.isEmpty()) {
        return control.rows
    }
    val template = control.rowTemplate ?: ListRowSpec(
        id = "{{id}}",
        title = "{{name}}",
        values = control.columns.associate { it.id to "{{${it.id}}}" },
        status = "{{status}}",
    )
    return control.items.mapIndexed { index, item -> hydrateRow(template, item, index) }
}

private fun hydrateRow(template: ListRowSpec, item: ListItemSpec, index: Int): ListRowSpec {
    val fallbackID = item.values["id"]?.takeIf { it.isNotBlank() } ?: "row-${index + 1}"
    fun render(value: String?): String? = value?.let { raw ->
        placeholderPattern.replace(raw) { match -> item.values[match.groupValues[1].trim()].orEmpty() }
            .takeIf { it.isNotBlank() }
    }
    return template.copy(
        id = render(template.id) ?: fallbackID,
        title = render(template.title) ?: item.values["title"] ?: item.values["name"],
        subtitle = render(template.subtitle) ?: item.values["subtitle"],
        status = render(template.status) ?: item.values["status"],
        values = template.values.mapValues { render(it.value).orEmpty() }.ifEmpty { item.values },
        tags = template.tags.map { tag ->
            tag.copy(
                id = render(tag.id) ?: tag.id,
                title = render(tag.title) ?: tag.title,
            )
        }.filter { it.title.isNotBlank() },
    )
}

private fun computedFileStateValue(context: RenderContext, placeholder: String): String? {
    val separator = placeholder.lastIndexOf('.')
    if (separator <= 0 || separator >= placeholder.lastIndex) {
        return null
    }
    val fieldID = placeholder.substring(0, separator)
    val property = placeholder.substring(separator + 1)
    val rawPath = context.fieldValues[fieldID] ?: context.configValues[fieldID]
    val path = rawPath?.takeIf { it.isNotBlank() }?.let { resolveUserPath(it, context.bundleRootPath) }
    return when (property) {
        "pathExtension" -> path?.substringAfterLast('.', "")?.lowercase().orEmpty()
        "exists" -> (path != null && File(path).exists()).toString()
        "fileSize" -> path?.let { File(it).takeIf(File::isFile)?.length()?.toString() }.orEmpty()
        "fileSizeGB" -> path?.let { File(it).takeIf(File::isFile)?.length()?.div(1_073_741_824.0)?.let { size -> "%.2f".format(size) } }.orEmpty()
        "parentDir" -> path?.let { File(it).parent }.orEmpty()
        "isIndexed" -> (path != null && isIndexedAlignment(path)).toString()
        "isSorted" -> (path != null && isSortedAlignment(path)).toString()
        else -> null
    }
}

fun resolveUserPath(path: String, bundleRoot: String): String {
    val expanded = path
        .replace("{{bundleRoot}}", bundleRoot)
        .replace("{{bundleWorkspace}}", bundleRoot)
        .replace("{{home}}", System.getProperty("user.home") ?: "/")
    return when {
        expanded.startsWith("~/") -> "${System.getProperty("user.home")}/${expanded.removePrefix("~/")}"
        File(expanded).isAbsolute -> expanded
        else -> File(bundleRoot, expanded).path
    }
}

fun shellQuote(value: String): String =
    if (Regex("""^[A-Za-z0-9_./\\:-]+$""").matches(value)) value else "'${value.replace("'", "'\\''")}'"

private fun isIndexedAlignment(path: String): Boolean {
    val withoutExtension = path.substringBeforeLast('.', path)
    return listOf("$path.bai", "$path.crai", "$path.csi", "$withoutExtension.bai", "$withoutExtension.crai", "$withoutExtension.csi")
        .any { File(it).exists() }
}

private fun isSortedAlignment(path: String): Boolean {
    if (isIndexedAlignment(path)) {
        return true
    }
    val name = File(path).name.lowercase()
    return name.contains(".sorted.") || name.contains("_sorted.") || name.endsWith(".sorted.bam") ||
        name.endsWith(".sorted.cram") || name.contains(".sort.") || name.contains("_sort.")
}
