package dev.guiforcli.compose.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.guiforcli.compose.model.ControlOption
import dev.guiforcli.compose.model.ControlSpec
import dev.guiforcli.compose.model.ListRowSpec
import dev.guiforcli.compose.runtime.ComposeAppState
import dev.guiforcli.compose.runtime.AppController
import dev.guiforcli.compose.runtime.hydrateRows
import dev.guiforcli.compose.runtime.rowContext

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ControlRenderer(
    control: ControlSpec,
    state: ComposeAppState,
    viewModel: AppController,
) {
    val effectiveControl = viewModel.effectiveControl(control)
    Column(
        Modifier
            .fillMaxWidth()
            .padding(top = 16.dp)
            .semantics {
                contentDescription = listOfNotNull(effectiveControl.label, effectiveControl.tooltip).joinToString(". ")
            },
    ) {
        Text(effectiveControl.label, fontWeight = FontWeight.SemiBold)
        effectiveControl.tooltip?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        state.dataSourceErrors[control.id]?.let {
            Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 6.dp))
        }
        when (effectiveControl.kind) {
            "text", "path" -> TextControl(effectiveControl, state, viewModel)
            "dropdown" -> DropdownControl(effectiveControl, state, viewModel)
            "toggle" -> ToggleControl(effectiveControl, state, viewModel)
            "checkboxGroup" -> CheckboxGroupControl(effectiveControl, state, viewModel)
            "libraryList" -> LibraryListControl(effectiveControl, state, viewModel)
            "configEditor" -> ConfigEditorControl(effectiveControl, state, viewModel)
            "infoGrid" -> InfoGridControl(effectiveControl)
            else -> Text("Unsupported control kind: ${effectiveControl.kind}")
        }
    }
}

@Composable
private fun TextControl(control: ControlSpec, state: ComposeAppState, viewModel: AppController) {
    OutlinedTextField(
        value = state.fieldValues[control.id].orEmpty(),
        onValueChange = { viewModel.setFieldValue(control.id, it) },
        placeholder = { control.placeholder?.let { Text(it) } },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DropdownControl(control: ControlSpec, state: ComposeAppState, viewModel: AppController) {
    val selectedID = state.fieldValues[control.id].orEmpty().ifBlank {
        control.options.firstOrNull { it.selected }?.id ?: control.options.firstOrNull()?.id.orEmpty()
    }
    FlowRow(Modifier.padding(top = 8.dp)) {
        control.options.forEach { option ->
            OutlinedButton(
                onClick = { viewModel.setFieldValue(control.id, option.id) },
                modifier = Modifier.padding(end = 8.dp, bottom = 8.dp),
            ) {
                Text(if (option.id == selectedID) "✓ ${option.title}" else option.title)
            }
        }
    }
}

@Composable
private fun ToggleControl(control: ControlSpec, state: ComposeAppState, viewModel: AppController) {
    val checked = state.fieldValues[control.id]?.toBooleanStrictOrNull() ?: false
    Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Switch(
            checked = checked,
            onCheckedChange = { viewModel.setFieldValue(control.id, it.toString()) },
        )
        Text(if (checked) "On" else "Off", Modifier.padding(start = 8.dp))
    }
}

@Composable
private fun CheckboxGroupControl(control: ControlSpec, state: ComposeAppState, viewModel: AppController) {
    val selected = state.checkedOptions[control.id].orEmpty()
    Column(Modifier.padding(top = 8.dp)) {
        control.options.forEach { option ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(
                    checked = option.id in selected,
                    onCheckedChange = { viewModel.setCheckedOption(control.id, option.id, it) },
                )
                Text(option.title)
            }
        }
    }
}

@Composable
private fun LibraryListControl(control: ControlSpec, state: ComposeAppState, viewModel: AppController) {
    val rows = hydrateRows(control)
    if (control.id in state.loadingDataSources) {
        Text("Loading ${control.label}...", Modifier.padding(top = 8.dp))
        return
    }
    if (rows.isEmpty()) {
        Text("No rows available.", Modifier.padding(top = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        return
    }
    Column(Modifier.padding(top = 8.dp)) {
        rows.forEach { row ->
            LibraryRow(row = row, control = control, state = state, viewModel = viewModel)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LibraryRow(
    row: ListRowSpec,
    control: ControlSpec,
    state: ComposeAppState,
    viewModel: AppController,
) {
    val context = rowContext(viewModel.renderContext(), row)
    Card(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Column(Modifier.padding(14.dp)) {
            Text(row.title ?: row.id.orEmpty(), fontWeight = FontWeight.SemiBold)
            row.subtitle?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            FlowRow(Modifier.padding(top = 8.dp)) {
                row.tags.forEach { tag ->
                    AssistChip(
                        onClick = {},
                        label = { Text(tag.title) },
                        modifier = Modifier.padding(end = 6.dp, bottom = 6.dp),
                    )
                }
                control.columns.forEach { column ->
                    row.values[column.id]?.takeIf { it.isNotBlank() }?.let { value ->
                        AssistChip(
                            onClick = {},
                            label = { Text("${column.title}: $value", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                            modifier = Modifier.padding(end = 6.dp, bottom = 6.dp),
                        )
                    }
                }
            }
            ActionRow(actions = control.rowActions, state = state, viewModel = viewModel, contextOverride = context)
        }
    }
}

@Composable
private fun ConfigEditorControl(control: ControlSpec, state: ComposeAppState, viewModel: AppController) {
    Column(Modifier.padding(top = 8.dp)) {
        control.settings.forEach { setting ->
            val value = state.configValues["${control.id}.${setting.id}"] ?: state.configValues[setting.id].orEmpty()
            OutlinedTextField(
                value = value,
                onValueChange = {
                    viewModel.setConfigValue("${control.id}.${setting.id}", it)
                    viewModel.setConfigValue(setting.id, it)
                    viewModel.setConfigValue(setting.key, it)
                },
                label = { Text(setting.label) },
                placeholder = { setting.placeholder?.let { Text(it) } },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp),
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun InfoGridControl(control: ControlSpec) {
    FlowRow(Modifier.padding(top = 8.dp)) {
        control.options.forEach { option: ControlOption ->
            AssistChip(
                onClick = {},
                label = { Text(option.title) },
                modifier = Modifier.padding(end = 8.dp, bottom = 8.dp).widthIn(max = 280.dp),
            )
        }
    }
}
