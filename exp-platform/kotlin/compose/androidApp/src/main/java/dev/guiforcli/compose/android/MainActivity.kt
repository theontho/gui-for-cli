package dev.guiforcli.compose.android

import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import dev.guiforcli.compose.runtime.AppController
import dev.guiforcli.compose.ui.GUIForCLIComposeApp
import kotlinx.coroutines.delay
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val launchStartedAt = SystemClock.elapsedRealtimeNanos()
        super.onCreate(savedInstanceState)
        setContent {
            val benchmarkOptions = remember { AndroidBenchmarkOptions.from(intent.extras) }
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
            if (benchmarkOptions.enabled) {
                val state by controller.state.collectAsState()
                LaunchedEffect(state.loading, state.error, state.manifest) {
                    if (!state.loading && (state.manifest != null || state.error != null)) {
                        val elapsedMs = (SystemClock.elapsedRealtimeNanos() - launchStartedAt) / 1_000_000.0
                        Log.i("GFCBenchmark", "ui_ready_ms=${"%.1f".format(Locale.US, elapsedMs)}")
                        if (benchmarkOptions.once) {
                            delay(250)
                            finish()
                        }
                    }
                }
            }
        }
    }
}

private data class AndroidBenchmarkOptions(
    val enabled: Boolean,
    val once: Boolean,
) {
    companion object {
        fun from(bundle: Bundle?): AndroidBenchmarkOptions {
            return AndroidBenchmarkOptions(
                enabled = bundle?.getString("benchmark") == "true",
                once = bundle?.getString("benchmark_once") == "true",
            )
        }
    }
}
