package dev.guiforcli.compose.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.guiforcli.compose.model.BundlePage
import dev.guiforcli.compose.model.PageSection
import dev.guiforcli.compose.runtime.ComposeAppState
import dev.guiforcli.compose.runtime.AppController

@Composable
fun PageRenderer(
    page: BundlePage,
    state: ComposeAppState,
    viewModel: AppController,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                resolvedTextIcon(page.textIcon, page.iconName, state.iconMap),
                style = MaterialTheme.typography.headlineMedium,
            )
            Column(Modifier.padding(start = 12.dp)) {
                Text(
                    page.title,
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.semantics { heading() },
                )
                Text(page.summary, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        page.sections.forEach { section ->
            SectionRenderer(section = section, state = state, viewModel = viewModel)
        }
    }
}

@Composable
private fun SectionRenderer(
    section: PageSection,
    state: ComposeAppState,
    viewModel: AppController,
) {
    Card(Modifier.fillMaxWidth().padding(top = 20.dp)) {
        Column(Modifier.padding(18.dp)) {
            section.title?.let { title ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TextIcon(section.textIcon, iconName = section.iconName, iconMap = state.iconMap)
                    Text(
                        title,
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.padding(start = 8.dp).semantics { heading() },
                    )
                }
            }
            section.subtitle?.let {
                Text(
                    it,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            val sectionError = state.dataSourceErrors[section.id]
            val sectionLoading = section.id in state.loadingDataSources
            if (sectionLoading) {
                Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator()
                    Text("Loading...", Modifier.padding(start = 12.dp))
                }
            }
            if (sectionError != null) {
                Text(
                    sectionError,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(top = 12.dp),
                )
            }
            section.controls.forEach { control ->
                ControlRenderer(control = control, state = state, viewModel = viewModel)
            }
            if (section.actions.isNotEmpty()) {
                if (section.controls.isNotEmpty()) {
                    HorizontalDivider(Modifier.padding(vertical = 12.dp))
                }
                ActionRow(actions = section.actions, state = state, viewModel = viewModel)
            }
        }
    }
}
