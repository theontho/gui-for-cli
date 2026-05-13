package dev.guiforcli.compose.runtime

import dev.guiforcli.compose.model.ActionConditionSpec
import dev.guiforcli.compose.model.ActionPrecheckSpec
import dev.guiforcli.compose.model.ActionSpec
import java.io.File

data class ActionPrecheckResult(
    val severity: Severity,
    val title: String,
    val message: String,
) {
    enum class Severity { Info, Warning }
}

fun isActionVisible(action: ActionSpec, context: RenderContext): Boolean =
    action.visibleWhen.all { conditionMatches(it, context) }

fun disabledReason(
    action: ActionSpec,
    context: RenderContext,
    fallback: String = "This action is not available.",
): String? {
    if (action.disabledWhen.none { conditionMatches(it, context) }) {
        return null
    }
    return action.disabledTooltip?.let { interpolate(it, context) } ?: fallback
}

fun conditionMatches(condition: ActionConditionSpec, context: RenderContext): Boolean {
    val value = contextValue(context, condition.placeholder)?.trim().orEmpty()
    if (condition.exists != null && condition.exists != value.isNotEmpty()) {
        return false
    }
    if (condition.equals != null && value != interpolate(condition.equals, context)) {
        return false
    }
    if (condition.notEquals != null && value == interpolate(condition.notEquals, context)) {
        return false
    }
    if (condition.inValues.isNotEmpty() && value !in condition.inValues.map { interpolate(it, context) }) {
        return false
    }
    if (value in condition.notInValues.map { interpolate(it, context) }) {
        return false
    }
    if (condition.lessThan != null && !compareNumeric(value, interpolate(condition.lessThan, context)) { left, right -> left < right }) {
        return false
    }
    if (condition.lessThanOrEqual != null && !compareNumeric(value, interpolate(condition.lessThanOrEqual, context)) { left, right -> left <= right }) {
        return false
    }
    if (condition.greaterThan != null && !compareNumeric(value, interpolate(condition.greaterThan, context)) { left, right -> left > right }) {
        return false
    }
    if (condition.greaterThanOrEqual != null && !compareNumeric(value, interpolate(condition.greaterThanOrEqual, context)) { left, right -> left >= right }) {
        return false
    }
    return true
}

fun evaluateActionPrecheck(precheck: ActionPrecheckSpec?, context: RenderContext): ActionPrecheckResult? {
    val rawRequired = precheck?.diskSpaceGB?.trim().orEmpty()
    if (rawRequired.isEmpty()) {
        return null
    }
    val requiredGB = evaluateNumeric(interpolate(rawRequired, context)) ?: return null
    if (requiredGB <= 0.0) {
        return null
    }
    val targetPath = interpolate(precheck?.diskSpacePath ?: "{{out_dir}}", context)
        .ifBlank { context.bundleRootPath }
    val resolvedPath = resolveUserPath(targetPath, context.bundleRootPath)
    val availableGB = availableGB(resolvedPath) ?: return null
    val isLow = availableGB < requiredGB
    val pathLabel = nearestExistingPath(resolvedPath)
    val message = if (isLow && precheck?.warningMessage != null) {
        interpolate(precheck.warningMessage, context)
    } else if (isLow) {
        "Need ${formatGB(requiredGB)} GB free at $pathLabel; ${formatGB(availableGB)} GB is available."
    } else {
        "Estimated ${formatGB(requiredGB)} GB needed at $pathLabel (${formatGB(availableGB)} GB free)."
    }
    return ActionPrecheckResult(
        severity = if (isLow) ActionPrecheckResult.Severity.Warning else ActionPrecheckResult.Severity.Info,
        title = if (isLow) "Not enough free disk space" else "Disk space estimate",
        message = message,
    )
}

fun evaluateNumeric(expression: String): Double? = NumericParser(expression).parse()

private fun compareNumeric(left: String, right: String, compare: (Double, Double) -> Boolean): Boolean {
    val leftValue = evaluateNumeric(left) ?: return false
    val rightValue = evaluateNumeric(right) ?: return false
    return compare(leftValue, rightValue)
}

private fun availableGB(path: String): Double? {
    val probe = File(nearestExistingPath(path))
    return if (probe.exists()) {
        probe.usableSpace / 1_073_741_824.0
    } else {
        null
    }
}

private fun nearestExistingPath(path: String): String {
    var probe = File(path)
    while (!probe.exists() && probe.parentFile != null) {
        probe = probe.parentFile
    }
    return probe.path
}

private fun formatGB(value: Double): String = when {
    value >= 100 -> "%.0f".format(value)
    value >= 10 -> "%.1f".format(value)
    else -> "%.2f".format(value)
}

private class NumericParser(private val text: String) {
    private var index = 0

    fun parse(): Double? {
        val value = expression()
        skipWhitespace()
        return if (index == text.length) value else null
    }

    private fun expression(): Double? {
        var value = term() ?: return null
        while (true) {
            skipWhitespace()
            value = when {
                consume('+') -> value + (term() ?: return null)
                consume('-') -> value - (term() ?: return null)
                else -> return value
            }
        }
    }

    private fun term(): Double? {
        var value = factor() ?: return null
        while (true) {
            skipWhitespace()
            value = when {
                consume('*') -> value * (factor() ?: return null)
                consume('/') -> value / (factor() ?: return null)
                else -> return value
            }
        }
    }

    private fun factor(): Double? {
        skipWhitespace()
        if (consume('+')) return factor()
        if (consume('-')) return factor()?.unaryMinus()
        if (consume('(')) {
            val value = expression()
            return if (consume(')')) value else null
        }
        return number()
    }

    private fun number(): Double? {
        skipWhitespace()
        val start = index
        while (index < text.length && (text[index].isDigit() || text[index] == '.')) {
            index += 1
        }
        return text.substring(start, index).takeIf { it.isNotEmpty() }?.toDoubleOrNull()
    }

    private fun skipWhitespace() {
        while (index < text.length && text[index].isWhitespace()) {
            index += 1
        }
    }

    private fun consume(expected: Char): Boolean {
        if (index >= text.length || text[index] != expected) {
            return false
        }
        index += 1
        return true
    }
}
