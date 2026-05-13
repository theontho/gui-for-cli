package dev.guiforcli.compose.runtime

import dev.guiforcli.compose.model.BundleManifest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale

data class BundleSession(
    val manifest: BundleManifest,
    val bundleRoot: File,
)

suspend fun loadBundleSession(
    bundleRoot: File,
    locale: Locale = Locale.getDefault(),
): BundleSession = withContext(Dispatchers.IO) {
    val manifestJson = JSONObject(File(bundleRoot, "manifest.json").readText())
    val pages = manifestJson.optJSONArray("pages") ?: JSONArray()
    if ((0 until pages.length()).all { pages.get(it) is String }) {
        val loadedPages = JSONArray()
        for (index in 0 until pages.length()) {
            val pageFileName = pages.getString(index)
            require(pageFileName.matches(Regex("""[A-Za-z0-9._-]+\.json"""))) {
                "Invalid page file name: $pageFileName"
            }
            loadedPages.put(JSONObject(File(bundleRoot, "pages/$pageFileName").readText()))
        }
        manifestJson.put("pages", loadedPages)
    }
    val rawManifest = parseManifest(manifestJson)
    val table = loadStrings(bundleRoot, rawManifest.defaultLocalizationCode, locale)
    BundleSession(rawManifest.localized(table), bundleRoot)
}

suspend fun loadManifestFromBundleRoot(
    bundleRoot: File,
    locale: Locale = Locale.getDefault(),
): BundleManifest = loadBundleSession(bundleRoot, locale).manifest

private fun loadStrings(
    bundleRoot: File,
    defaultCode: String,
    locale: Locale,
): Map<String, String> {
    val localeCode = locale.toLanguageTag()
    val languageCode = locale.language
    val strings = linkedMapOf<String, String>()
    readOptionalStrings(File(bundleRoot, "strings/strings.$defaultCode.toml"))?.let(strings::putAll)
    for (candidate in listOf(localeCode, languageCode).distinct()) {
        if (candidate.isNotBlank() && candidate != defaultCode) {
            readOptionalStrings(File(bundleRoot, "strings/strings.$candidate.toml"))?.let(strings::putAll)
        }
    }
    return strings
}

private fun readOptionalStrings(file: File): Map<String, String>? =
    if (file.isFile) parseTomlStringTable(file.readText()) else null
