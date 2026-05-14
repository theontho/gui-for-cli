package dev.guiforcli.compose.desktop

import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import dev.guiforcli.compose.runtime.AppController
import dev.guiforcli.compose.ui.GUIForCLIComposeApp
import kotlinx.coroutines.delay
import java.io.File
import java.util.Locale

fun main(args: Array<String>) = application {
    val options = remember { DesktopBenchmarkOptions.parse(args) }
    val launchStartedAt = remember { System.nanoTime() }
    Window(
        onCloseRequest = ::exitApplication,
        title = "GUI for CLI Compose Desktop",
    ) {
        val scope = rememberCoroutineScope()
        val controller = remember {
            AppController(
                scope = scope,
                loadSession = { DesktopBundleLoader(args).load() },
            )
        }
        DisposableEffect(controller) {
            controller.start()
            onDispose { controller.close() }
        }
        GUIForCLIComposeApp(controller)
        if (options.enabled) {
            val state by controller.state.collectAsState()
            LaunchedEffect(state.loading, state.error, state.manifest) {
                if (!state.loading && (state.manifest != null || state.error != null)) {
                    val elapsedMs = (System.nanoTime() - launchStartedAt) / 1_000_000.0
                    val line = "gfc-compose benchmark ui_ready_ms=${"%.1f".format(Locale.US, elapsedMs)}"
                    println(line)
                    options.outputPath?.let { File(it).appendText("$line\n") }
                    if (options.once) {
                        delay(250)
                        exitApplication()
                    }
                }
            }
        }
    }
}

private data class DesktopBenchmarkOptions(
    val enabled: Boolean = false,
    val once: Boolean = false,
    val outputPath: String? = null,
) {
    companion object {
        fun parse(args: Array<String>): DesktopBenchmarkOptions {
            var enabled = false
            var once = false
            var outputPath: String? = null
            var index = 0
            while (index < args.size) {
                when (val arg = args[index]) {
                    "--benchmark", "--benchmark-full" -> enabled = true
                    "--once" -> once = true
                    "--benchmark-output" -> {
                        outputPath = args.getOrNull(index + 1) ?: error("--benchmark-output requires a value.")
                        index += 1
                    }
                    else -> if (arg.startsWith("--benchmark-output=")) {
                        outputPath = arg.substringAfter("=")
                    }
                }
                index += 1
            }
            return DesktopBenchmarkOptions(enabled = enabled, once = once, outputPath = outputPath)
        }
    }
}
