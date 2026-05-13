package dev.guiforcli.compose.desktop

import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import dev.guiforcli.compose.runtime.AppController
import dev.guiforcli.compose.ui.GUIForCLIComposeApp

fun main(args: Array<String>) = application {
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
    }
}
