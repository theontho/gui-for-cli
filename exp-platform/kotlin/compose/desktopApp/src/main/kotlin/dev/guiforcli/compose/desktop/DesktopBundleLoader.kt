package dev.guiforcli.compose.desktop

import dev.guiforcli.compose.runtime.BundleSession
import dev.guiforcli.compose.runtime.loadBundleSession
import java.io.File
import java.util.Locale

class DesktopBundleLoader(private val args: Array<String>) {
    suspend fun load(locale: Locale = Locale.getDefault()): BundleSession {
        val bundleRoot = resolveBundleRoot()
        return loadBundleSession(bundleRoot, locale)
    }

    private fun resolveBundleRoot(): File {
        val fromArgs = bundleArgument()
        val explicit = fromArgs ?: System.getenv("GFC_BUNDLE_ROOT")
        if (!explicit.isNullOrBlank()) {
            return File(explicit).absoluteFile
        }
        return File(resolveRepoRoot(), "examples/WGSExtract")
    }

    private fun bundleArgument(): String? {
        for ((index, arg) in args.withIndex()) {
            if (arg == "--bundle") {
                return args.getOrNull(index + 1)
            }
            if (arg.startsWith("--bundle=")) {
                return arg.substringAfter("=")
            }
        }
        return null
    }

    private fun resolveRepoRoot(): File {
        var directory = File(System.getProperty("user.dir")).absoluteFile
        while (true) {
            if (File(directory, "platform/apple/Package.swift").isFile && File(directory, "examples").isDirectory) {
                return directory
            }
            directory = directory.parentFile ?: error(
                "Could not find repository root from ${System.getProperty("user.dir")}. " +
                    "Set GFC_BUNDLE_ROOT or run from inside the GUI for CLI repository.",
            )
        }
    }
}
