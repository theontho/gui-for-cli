package dev.guiforcli.compose.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import dev.guiforcli.compose.runtime.AppController
import dev.guiforcli.compose.ui.GUIForCLIComposeApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val context = LocalContext.current.applicationContext
            val scope = rememberCoroutineScope()
            val controller = remember {
                AppController(
                    scope = scope,
                    loadSession = { AndroidBundleLoader(context).load() },
                    externalProcessesEnabled = false,
                )
            }
            DisposableEffect(controller) {
                controller.start()
                onDispose { controller.close() }
            }
            GUIForCLIComposeApp(controller)
        }
    }
}
