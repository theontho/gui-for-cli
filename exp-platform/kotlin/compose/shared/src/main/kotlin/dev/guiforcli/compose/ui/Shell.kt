package dev.guiforcli.compose.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Output
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.guiforcli.compose.model.BundleManifest
import dev.guiforcli.compose.model.BundlePage
import dev.guiforcli.compose.runtime.ComposeAppState
import dev.guiforcli.compose.runtime.AppController

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GUIForCLIShell(
    state: ComposeAppState,
    viewModel: AppController,
    compactNavigation: Boolean = false,
) {
    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    Text(
                        state.manifest?.displayName ?: "GUI for CLI Compose",
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                actions = {
                    val label = if (state.terminalVisible) "Hide terminal output" else "Show terminal output"
                    IconButton(
                        onClick = viewModel::toggleTerminalVisibility,
                        modifier = Modifier.semantics { contentDescription = label },
                    ) {
                        Icon(if (state.terminalVisible) Icons.Default.VisibilityOff else Icons.Default.Visibility, label)
                    }
                },
                scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior(),
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            val selectedPage = state.selectedPage
            when {
                state.loading -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                state.error != null -> ErrorMessage(state.error)
                state.manifest != null && compactNavigation -> CompactShell(
                    state = state,
                    manifest = state.manifest,
                    selectedPage = selectedPage,
                    viewModel = viewModel,
                )
                state.manifest != null && selectedPage != null -> LoadedShell(
                    state = state,
                    manifest = state.manifest,
                    selectedPage = selectedPage,
                    viewModel = viewModel,
                )
            }
        }
    }
}

@Composable
private fun CompactShell(
    state: ComposeAppState,
    manifest: BundleManifest,
    selectedPage: BundlePage?,
    viewModel: AppController,
) {
    if (selectedPage == null) {
        PageList(
            manifest = manifest,
            state = state,
            selectedPageID = "",
            onSelectPage = viewModel::selectPage,
            modifier = Modifier.fillMaxSize(),
        )
        return
    }

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = { viewModel.selectPage("") }) {
                Text("Pages")
            }
            Text(
                selectedPage.title,
                modifier = Modifier.weight(1f).padding(start = 8.dp),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                fontWeight = FontWeight.SemiBold,
            )
        }
        HorizontalDivider()
        PageRenderer(
            page = selectedPage,
            state = state,
            viewModel = viewModel,
            modifier = Modifier.weight(1f).fillMaxWidth(),
        )
        if (state.terminalVisible) {
            HorizontalDivider()
            TerminalPane(
                state = state,
                viewModel = viewModel,
                terminalTextDirection = manifest.terminalTextDirection,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun LoadedShell(
    state: ComposeAppState,
    manifest: BundleManifest,
    selectedPage: BundlePage,
    viewModel: AppController,
) {
    Row(Modifier.fillMaxSize()) {
        PageList(
            manifest = manifest,
            state = state,
            selectedPageID = selectedPage.id,
            onSelectPage = viewModel::selectPage,
            modifier = Modifier.width(260.dp).fillMaxHeight(),
        )
        VerticalDivider(Modifier.fillMaxHeight().width(1.dp))
        Column(Modifier.weight(1f).fillMaxHeight()) {
            PageRenderer(
                page = selectedPage,
                state = state,
                viewModel = viewModel,
                modifier = Modifier.weight(1f).fillMaxWidth(),
            )
            if (state.terminalVisible) {
                HorizontalDivider()
                TerminalPane(
                    state = state,
                    viewModel = viewModel,
                    terminalTextDirection = manifest.terminalTextDirection,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun PageList(
    manifest: BundleManifest,
    state: ComposeAppState,
    selectedPageID: String,
    onSelectPage: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val bottomIDs = setOf("library", "settings")
    val primaryPages = manifest.pages.filterNot { it.id in bottomIDs }
    val bottomPages = manifest.pages.filter { it.id in bottomIDs }
    Column(modifier.padding(vertical = 12.dp)) {
        ListItem(
            headlineContent = { Text(manifest.displayName, fontWeight = FontWeight.SemiBold) },
            supportingContent = {
                Text(manifest.summary, maxLines = 3, overflow = TextOverflow.Ellipsis)
            },
            leadingContent = { TextIcon(manifest.textIcon, iconName = manifest.iconName, iconMap = state.iconMap) },
        )
        HorizontalDivider()
        LazyColumn(Modifier.weight(1f)) {
            groupedPages(primaryPages).forEach { (group, pages) ->
                if (group != null) {
                    item {
                        Text(
                            group,
                            modifier = Modifier.padding(start = 28.dp, end = 16.dp, top = 16.dp, bottom = 6.dp),
                            fontWeight = FontWeight.Medium,
                        )
                    }
                }
                items(pages, key = { it.id }) { page ->
                    PageNavigationItem(page, selectedPageID == page.id, state, onSelectPage)
                }
            }
        }
        if (bottomPages.isNotEmpty()) {
            HorizontalDivider()
            bottomPages.forEach { page ->
                PageNavigationItem(page, selectedPageID == page.id, state, onSelectPage)
            }
        }
    }
}

@Composable
private fun PageNavigationItem(
    page: BundlePage,
    selected: Boolean,
    state: ComposeAppState,
    onSelectPage: (String) -> Unit,
) {
    NavigationDrawerItem(
        selected = selected,
        onClick = { onSelectPage(page.id) },
        icon = { TextIcon(page.textIcon, iconName = page.iconName, iconMap = state.iconMap) },
        label = { Text(page.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        modifier = Modifier.padding(NavigationDrawerItemDefaults.ItemPadding),
    )
}

private fun groupedPages(pages: List<BundlePage>): List<Pair<String?, List<BundlePage>>> {
    val groups = linkedMapOf<String?, MutableList<BundlePage>>()
    for (page in pages) {
        groups.getOrPut(page.sidebarGroup) { mutableListOf() }.add(page)
    }
    return groups.map { it.key to it.value }
}

@Composable
private fun ErrorMessage(message: String) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Default.Output, contentDescription = null)
        Spacer(Modifier.padding(4.dp))
        Text("Could not load bundle", fontWeight = FontWeight.SemiBold)
        Text(message)
    }
}
