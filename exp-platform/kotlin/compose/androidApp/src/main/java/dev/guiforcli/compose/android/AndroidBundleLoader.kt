package dev.guiforcli.compose.android

import android.content.Context
import dev.guiforcli.compose.runtime.BundleSession
import dev.guiforcli.compose.runtime.loadBundleSession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale

class AndroidBundleLoader(
    private val context: Context,
    private val assetBundleRoot: String = "WGSExtract",
) {
    suspend fun load(locale: Locale = Locale.getDefault()): BundleSession = withContext(Dispatchers.IO) {
        loadBundleSession(extractBundle(), locale)
    }

    private fun extractBundle(): File {
        val target = File(context.filesDir, "bundles/$assetBundleRoot")
        if (File(target, "manifest.json").isFile) {
            return target
        }
        if (target.exists()) {
            target.deleteRecursively()
        }
        copyAssetTree(assetBundleRoot, target)
        return target
    }

    private fun copyAssetTree(assetPath: String, target: File) {
        val children = context.assets.list(assetPath)?.toList().orEmpty()
        if (children.isEmpty()) {
            target.parentFile?.mkdirs()
            context.assets.open(assetPath).use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            if (target.extension == "sh" || target.extension == "py") {
                target.setExecutable(true, false)
            }
            return
        }
        target.mkdirs()
        for (child in children) {
            copyAssetTree("$assetPath/$child", File(target, child))
        }
    }
}
