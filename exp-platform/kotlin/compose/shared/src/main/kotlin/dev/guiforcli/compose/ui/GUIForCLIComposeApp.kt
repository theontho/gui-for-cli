package dev.guiforcli.compose.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import dev.guiforcli.compose.runtime.AppController
import java.util.Locale

@Composable
fun GUIForCLIComposeApp(controller: AppController, compactNavigation: Boolean = false) {
    val state by controller.state.collectAsState()
    val layoutDirection = if (Locale.getDefault().language in setOf("ar", "fa", "he", "ur")) {
        LayoutDirection.Rtl
    } else {
        LayoutDirection.Ltr
    }
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()) {
        CompositionLocalProvider(LocalLayoutDirection provides layoutDirection) {
            GUIForCLIShell(state = state, viewModel = controller, compactNavigation = compactNavigation)
        }
    }
}
