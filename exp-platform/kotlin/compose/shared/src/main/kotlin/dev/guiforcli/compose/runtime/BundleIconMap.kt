package dev.guiforcli.compose.runtime

data class BundleIconMap(
    val sources: Map<String, Map<String, String>> = emptyMap(),
) {
    fun resolving(key: String?, source: String = EmojiSource, fallbackToKey: Boolean = false): String? {
        val trimmed = key?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return sources[source]?.get(trimmed) ?: if (fallbackToKey) trimmed else null
    }

    fun merging(overrides: BundleIconMap): BundleIconMap {
        val merged = sources.mapValues { it.value.toMutableMap() }.toMutableMap()
        for ((source, values) in overrides.sources) {
            merged.getOrPut(source) { mutableMapOf() }.putAll(values)
        }
        return BundleIconMap(merged)
    }

    companion object {
        const val EmojiSource = "emoji"
    }
}

fun parseIconMapToml(text: String): BundleIconMap {
    val sources = linkedMapOf<String, MutableMap<String, String>>()
    var currentSource: String? = null
    for ((offset, rawLine) in text.lineSequence().withIndex()) {
        val lineNumber = offset + 1
        val line = rawLine.trim()
        if (line.isEmpty() || line.startsWith("#")) {
            continue
        }
        if (line.startsWith("[") && line.endsWith("]")) {
            val source = line.drop(1).dropLast(1).trim()
            require(source.isNotEmpty()) { "Invalid icon map TOML at line $lineNumber: $rawLine" }
            currentSource = source
            sources.getOrPut(source) { linkedMapOf() }
            continue
        }
        val source = currentSource
        val equals = findUnescapedEquals(line)
        require(source != null && equals > 0) { "Invalid icon map TOML at line $lineNumber: $rawLine" }
        val key = unquoteTomlKey(line.substring(0, equals).trim())
        sources.getOrPut(source) { linkedMapOf() }[key] =
            parseTomlQuotedValue(line.substring(equals + 1).trimStart(), lineNumber, rawLine)
    }
    return BundleIconMap(sources)
}

private fun findUnescapedEquals(line: String): Int {
    var escaped = false
    var inString = false
    for (index in line.indices) {
        val character = line[index]
        if (escaped) {
            escaped = false
            continue
        }
        if (character == '\\') {
            escaped = true
            continue
        }
        if (character == '"') {
            inString = !inString
            continue
        }
        if (!inString && character == '=') {
            return index
        }
    }
    return -1
}

private fun unquoteTomlKey(key: String): String =
    if (key.startsWith("\"") && key.endsWith("\"")) key.substring(1, key.length - 1) else key

private fun parseTomlQuotedValue(rawValue: String, lineNumber: Int, rawLine: String): String {
    require(rawValue.startsWith("\"")) { "Invalid icon map TOML at line $lineNumber: $rawLine" }
    var escaped = false
    for (index in 1 until rawValue.length) {
        val character = rawValue[index]
        if (escaped) {
            escaped = false
            continue
        }
        if (character == '\\') {
            escaped = true
            continue
        }
        if (character == '"') {
            val trailing = rawValue.substring(index + 1).trim()
            require(trailing.isEmpty() || trailing.startsWith("#")) {
                "Invalid icon map TOML at line $lineNumber: $rawLine"
            }
            return unescapeTomlIconValue(rawValue.substring(1, index), lineNumber, rawLine)
        }
    }
    error("Invalid icon map TOML at line $lineNumber: $rawLine")
}

private fun unescapeTomlIconValue(value: String, lineNumber: Int, rawLine: String): String = buildString {
    var index = 0
    while (index < value.length) {
        val character = value[index]
        if (character != '\\') {
            append(character)
            index += 1
            continue
        }
        index += 1
        require(index < value.length) { "Invalid icon map TOML at line $lineNumber: $rawLine" }
        when (val escaped = value[index]) {
            'n' -> append('\n')
            'r' -> append('\r')
            't' -> append('\t')
            '"' -> append('"')
            '\\' -> append('\\')
            'u', 'U' -> {
                val length = if (escaped == 'u') 4 else 8
                val hexStart = index + 1
                val hexEnd = hexStart + length
                require(hexEnd <= value.length) { "Invalid icon map TOML at line $lineNumber: $rawLine" }
                val codePoint = value.substring(hexStart, hexEnd).toIntOrNull(16)
                require(codePoint != null) { "Invalid icon map TOML at line $lineNumber: $rawLine" }
                appendCodePoint(codePoint)
                index += length
            }
            else -> error("Invalid icon map TOML at line $lineNumber: $rawLine")
        }
        index += 1
    }
}
