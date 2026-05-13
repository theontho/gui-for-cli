package dev.guiforcli.compose.runtime

import dev.guiforcli.compose.model.ActionConfirmationSpec
import dev.guiforcli.compose.model.ActionPrecheckSpec
import dev.guiforcli.compose.model.ActionSpec
import dev.guiforcli.compose.model.BundleManifest
import dev.guiforcli.compose.model.BundlePage
import dev.guiforcli.compose.model.ConfigSettingSpec
import dev.guiforcli.compose.model.ControlOption
import dev.guiforcli.compose.model.ControlSpec
import dev.guiforcli.compose.model.ExitCodeReferenceEntry
import dev.guiforcli.compose.model.ListColumnSpec
import dev.guiforcli.compose.model.ListRowSpec
import dev.guiforcli.compose.model.PageSection
import dev.guiforcli.compose.model.SetupSpec
import dev.guiforcli.compose.model.SetupStep
import dev.guiforcli.compose.model.TagSpec

fun parseTomlStringTable(text: String): Map<String, String> {
    val values = linkedMapOf<String, String>()
    for (rawLine in text.lineSequence()) {
        val line = rawLine.trim()
        if (line.isEmpty() || line.startsWith("#")) {
            continue
        }
        val split = line.indexOf('=')
        if (split <= 0) {
            continue
        }
        val key = unquoteTomlString(line.substring(0, split).trim())
        val value = unquoteTomlString(line.substring(split + 1).trim())
        values[key] = value
    }
    return values
}

fun BundleManifest.localized(strings: Map<String, String>): BundleManifest =
    copy(
        displayName = strings.localize(displayName) ?: displayName,
        summary = strings.localize(summary) ?: summary,
        setup = setup.localized(strings),
        exitCodeReference = exitCodeReference.map { it.localized(strings) },
        pages = pages.map { it.localized(strings) },
    )

fun Map<String, String>.localize(value: String?): String? = value?.let { this[it] ?: it }

private fun SetupSpec.localized(strings: Map<String, String>): SetupSpec =
    copy(steps = steps.map { it.localized(strings) })

private fun SetupStep.localized(strings: Map<String, String>): SetupStep =
    copy(label = strings.localize(label) ?: label)

private fun ExitCodeReferenceEntry.localized(strings: Map<String, String>): ExitCodeReferenceEntry =
    copy(title = strings.localize(title) ?: title, summary = strings.localize(summary) ?: summary)

private fun BundlePage.localized(strings: Map<String, String>): BundlePage =
    copy(
        title = strings.localize(title) ?: title,
        summary = strings.localize(summary) ?: summary,
        sidebarGroup = strings.localize(sidebarGroup),
        sections = sections.map { it.localized(strings) },
    )

private fun PageSection.localized(strings: Map<String, String>): PageSection =
    copy(
        title = strings.localize(title),
        subtitle = strings.localize(subtitle),
        controls = controls.map { it.localized(strings) },
        actions = actions.map { it.localized(strings) },
    )

private fun ControlSpec.localized(strings: Map<String, String>): ControlSpec =
    copy(
        label = strings.localize(label) ?: label,
        placeholder = strings.localize(placeholder),
        tooltip = strings.localize(tooltip),
        options = options.map { it.localized(strings) },
        columns = columns.map { it.localized(strings) },
        rows = rows.map { it.localized(strings) },
        rowTemplate = rowTemplate?.localized(strings),
        rowActions = rowActions.map { it.localized(strings) },
        settings = settings.map { it.localized(strings) },
    )

private fun ControlOption.localized(strings: Map<String, String>): ControlOption =
    copy(title = strings.localize(title) ?: title, subtitle = strings.localize(subtitle))

private fun ListColumnSpec.localized(strings: Map<String, String>): ListColumnSpec =
    copy(title = strings.localize(title) ?: title)

private fun ListRowSpec.localized(strings: Map<String, String>): ListRowSpec =
    copy(
        title = strings.localize(title),
        subtitle = strings.localize(subtitle),
        status = strings.localize(status),
        tags = tags.map { it.localized(strings) },
    )

private fun TagSpec.localized(strings: Map<String, String>): TagSpec =
    copy(title = strings.localize(title) ?: title)

private fun ActionSpec.localized(strings: Map<String, String>): ActionSpec =
    copy(
        title = strings.localize(title) ?: title,
        tooltip = strings.localize(tooltip),
        disabledTooltip = strings.localize(disabledTooltip),
        precheck = precheck?.localized(strings),
        confirm = confirm?.localized(strings),
    )

private fun ActionPrecheckSpec.localized(strings: Map<String, String>): ActionPrecheckSpec =
    copy(warningMessage = strings.localize(warningMessage))

private fun ActionConfirmationSpec.localized(strings: Map<String, String>): ActionConfirmationSpec =
    copy(
        title = strings.localize(title) ?: title,
        message = strings.localize(message),
        confirmButtonTitle = strings.localize(confirmButtonTitle) ?: confirmButtonTitle,
        cancelButtonTitle = strings.localize(cancelButtonTitle) ?: cancelButtonTitle,
        requiredText = strings.localize(requiredText) ?: requiredText,
        prompt = strings.localize(prompt),
    )

private fun ConfigSettingSpec.localized(strings: Map<String, String>): ConfigSettingSpec =
    copy(
        label = strings.localize(label) ?: label,
        placeholder = strings.localize(placeholder),
        tooltip = strings.localize(tooltip),
        options = options.map { it.localized(strings) },
    )

private fun unquoteTomlString(value: String): String {
    val trimmed = value.trim().removeSuffix(",")
    if (trimmed.length < 2 || trimmed.first() != '"' || trimmed.last() != '"') {
        return trimmed
    }
    val body = trimmed.substring(1, trimmed.length - 1)
    return buildString {
        var index = 0
        while (index < body.length) {
            val ch = body[index]
            if (ch == '\\' && index + 1 < body.length) {
                append(
                    when (val escaped = body[index + 1]) {
                        'n' -> '\n'
                        'r' -> '\r'
                        't' -> '\t'
                        '"' -> '"'
                        '\\' -> '\\'
                        else -> escaped
                    },
                )
                index += 2
            } else {
                append(ch)
                index += 1
            }
        }
    }
}
