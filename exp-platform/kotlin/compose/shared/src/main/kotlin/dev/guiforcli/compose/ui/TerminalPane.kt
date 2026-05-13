package dev.guiforcli.compose.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import dev.guiforcli.compose.runtime.ComposeAppState
import dev.guiforcli.compose.runtime.AppController
import dev.guiforcli.compose.runtime.TerminalStatus
import dev.guiforcli.compose.runtime.TerminalTab

@Composable
fun TerminalPane(
    state: ComposeAppState,
    viewModel: AppController,
    terminalTextDirection: String,
    modifier: Modifier = Modifier,
) {
    val selected = state.terminalTabs.firstOrNull { it.id == state.selectedTerminalTabID }
        ?: state.terminalTabs.firstOrNull()
        ?: TerminalTab.main()
    Column(modifier.height(230.dp).background(MaterialTheme.colorScheme.surfaceVariant)) {
        Row(
            Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 8.dp, vertical = 6.dp),
        ) {
            state.terminalTabs.forEach { tab ->
                AssistChip(
                    onClick = { viewModel.selectTerminalTab(tab.id) },
                    label = {
                        Text(
                            statusPrefix(tab.status) + tab.title,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    },
                    trailingIcon = {
                        if (tab.status == TerminalStatus.Running) {
                            IconButton(
                                onClick = { viewModel.cancelCommand(tab.id) },
                                modifier = Modifier.semantics { contentDescription = "Cancel ${tab.title}" },
                            ) {
                                Icon(Icons.Default.Stop, contentDescription = null)
                            }
                        } else if (tab.dismissible) {
                            IconButton(
                                onClick = { viewModel.closeTerminalTab(tab.id) },
                                modifier = Modifier.semantics { contentDescription = "Close ${tab.title}" },
                            ) {
                                Icon(Icons.Default.Close, contentDescription = null)
                            }
                        }
                    },
                    modifier = Modifier.padding(end = 6.dp),
                )
            }
        }
        CompositionLocalProvider(
            LocalLayoutDirection provides if (terminalTextDirection == "rtl") LayoutDirection.Rtl else LayoutDirection.Ltr,
        ) {
            Text(
                selected.lines.joinToString("\n"),
                fontFamily = FontFamily.Monospace,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(12.dp),
            )
        }
    }
}

private fun statusPrefix(status: TerminalStatus): String = when (status) {
    TerminalStatus.Running -> "⏳ "
    TerminalStatus.Success -> "✓ "
    TerminalStatus.Warning -> "⚠ "
    TerminalStatus.Failed -> "✕ "
    TerminalStatus.Cancelled -> "⏹ "
    TerminalStatus.Idle -> ""
}
