package dev.guiforcli.compose.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.guiforcli.compose.model.ActionSpec
import dev.guiforcli.compose.runtime.ComposeAppState
import dev.guiforcli.compose.runtime.AppController
import dev.guiforcli.compose.runtime.RenderContext
import dev.guiforcli.compose.runtime.disabledReason
import dev.guiforcli.compose.runtime.evaluateActionPrecheck
import dev.guiforcli.compose.runtime.interpolate
import dev.guiforcli.compose.runtime.isActionVisible
import dev.guiforcli.compose.runtime.missingRequiredPlaceholders

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ActionRow(
    actions: List<ActionSpec>,
    state: ComposeAppState,
    viewModel: AppController,
    contextOverride: RenderContext? = null,
) {
    val context = contextOverride ?: viewModel.renderContext()
    FlowRow {
        actions.filter { isActionVisible(it, context) }.forEach { action ->
            ActionButton(action = action, state = state, viewModel = viewModel, context = context)
        }
    }
}

@Composable
private fun ActionButton(
    action: ActionSpec,
    state: ComposeAppState,
    viewModel: AppController,
    context: RenderContext,
) {
    var showConfirm by remember(action.id) { mutableStateOf(false) }
    val missing = missingRequiredPlaceholders(action.command, context)
    val explicitDisabled = disabledReason(action, context)
    val disabledText = when {
        !state.externalProcessesEnabled -> "Command execution is not supported on this platform."
        explicitDisabled != null -> explicitDisabled
        missing.isNotEmpty() -> missing.joinToString(prefix = "Fill in ", transform = { it.substringAfterLast('.') })
        else -> null
    }
    val precheck = evaluateActionPrecheck(action.precheck, context)
    val run = {
        if (action.confirm != null) {
            showConfirm = true
        } else {
            viewModel.runAction(action, context)
        }
    }
    Column(Modifier.padding(end = 8.dp, bottom = 8.dp)) {
        val colors = if (action.destructive || action.role == "destructive") {
            ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
        } else {
            ButtonDefaults.buttonColors()
        }
        if (disabledText == null) {
            Button(onClick = run, colors = colors) {
                Text(action.textIcon?.let { "$it ${action.title}" } ?: action.title)
            }
        } else {
            OutlinedButton(onClick = {}, enabled = false) {
                Text(action.title)
            }
            Text(disabledText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        precheck?.let {
            Text(
                it.message,
                style = MaterialTheme.typography.bodySmall,
                color = if (it.severity.name == "Warning") MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    if (showConfirm) {
        val confirm = action.confirm
        if (confirm != null) {
            var confirmationText by remember(confirm.requiredText) { mutableStateOf("") }
            val requiredText = confirm.requiredText?.let { interpolate(it, context) }
            val canConfirm = requiredText == null || confirmationText == requiredText
            AlertDialog(
                onDismissRequest = { showConfirm = false },
                title = { Text(interpolate(confirm.title, context)) },
                text = {
                    Column {
                        Text(confirm.message?.let { interpolate(it, context) }.orEmpty())
                        if (requiredText != null) {
                            OutlinedTextField(
                                value = confirmationText,
                                onValueChange = { confirmationText = it },
                                label = { Text(confirm.prompt?.let { interpolate(it, context) } ?: requiredText) },
                                singleLine = true,
                            )
                        }
                    }
                },
                confirmButton = {
                    TextButton(
                        onClick = {
                            showConfirm = false
                            viewModel.runAction(action, context)
                        },
                        enabled = canConfirm,
                    ) {
                        Text(interpolate(confirm.confirmButtonTitle, context))
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showConfirm = false }) {
                        Text(interpolate(confirm.cancelButtonTitle, context))
                    }
                },
            )
        }
    }
}
