package dev.guiforcli.compose.runtime

import dev.guiforcli.compose.model.ActionSpec
import dev.guiforcli.compose.model.BundleManifest
import dev.guiforcli.compose.model.BundlePage
import dev.guiforcli.compose.model.ControlSpec
import dev.guiforcli.compose.model.DataSourcePayload
import dev.guiforcli.compose.model.PageSection
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

data class ComposeAppState(
    val loading: Boolean = true,
    val error: String? = null,
    val manifest: BundleManifest? = null,
    val iconMap: BundleIconMap = BundleIconMap(),
    val bundleRootPath: String = "",
    val selectedPageID: String? = null,
    val fieldValues: Map<String, String> = emptyMap(),
    val checkedOptions: Map<String, Set<String>> = emptyMap(),
    val configValues: Map<String, String> = emptyMap(),
    val dataValues: Map<String, String> = emptyMap(),
    val dataPayloads: Map<String, DataSourcePayload> = emptyMap(),
    val loadingDataSources: Set<String> = emptySet(),
    val dataSourceErrors: Map<String, String> = emptyMap(),
    val terminalTabs: List<TerminalTab> = listOf(TerminalTab.main()),
    val selectedTerminalTabID: String = TerminalTab.MainTabID,
    val terminalVisible: Boolean = true,
    val externalProcessesEnabled: Boolean = true,
) {
    val selectedPage: BundlePage?
        get() = selectedPageID?.let { pageID -> manifest?.pages?.firstOrNull { it.id == pageID } }
}

class AppController(
    private val scope: CoroutineScope,
    private val loadSession: suspend () -> BundleSession,
    private val externalProcessesEnabled: Boolean = true,
    private val selectInitialPage: Boolean = true,
) {
    private val _state = MutableStateFlow(ComposeAppState(externalProcessesEnabled = externalProcessesEnabled))
    val state: StateFlow<ComposeAppState> = _state
    private val runningProcesses = ConcurrentHashMap<String, Process>()
    private val runningJobs = ConcurrentHashMap<String, Job>()
    private val started = AtomicBoolean(false)
    private val dataSourceRefreshVersion = AtomicLong(0)

    fun start() {
        if (!started.compareAndSet(false, true)) {
            return
        }
        scope.launch {
            runCatching { loadSession() }
                .onSuccess(::installSession)
                .onFailure { error ->
                    _state.update { it.copy(loading = false, error = error.message ?: error.toString()) }
                }
        }
    }

    fun close() {
        runningProcesses.values.forEach { it.destroy() }
        runningJobs.values.forEach { it.cancel() }
    }

    fun selectPage(pageID: String) {
        _state.update { it.copy(selectedPageID = pageID) }
        refreshDataSources()
    }

    fun setFieldValue(id: String, value: String) {
        _state.update { it.copy(fieldValues = it.fieldValues + (id to value)) }
    }

    fun setConfigValue(id: String, value: String) {
        _state.update { it.copy(configValues = it.configValues + (id to value)) }
    }

    fun setCheckedOption(controlID: String, optionID: String, checked: Boolean) {
        _state.update { state ->
            val current = state.checkedOptions[controlID].orEmpty()
            state.copy(
                checkedOptions = state.checkedOptions + (controlID to if (checked) current + optionID else current - optionID),
            )
        }
    }

    fun toggleTerminalVisibility() {
        _state.update { it.copy(terminalVisible = !it.terminalVisible) }
    }

    fun selectTerminalTab(tabID: String) {
        _state.update { it.copy(selectedTerminalTabID = tabID) }
    }

    fun closeTerminalTab(tabID: String) {
        cancelCommand(tabID)
        _state.update { state ->
            val remaining = state.terminalTabs.filterNot { it.id == tabID && it.dismissible }
            state.copy(
                terminalTabs = remaining,
                selectedTerminalTabID = remaining.firstOrNull()?.id ?: TerminalTab.MainTabID,
            )
        }
    }

    fun cancelCommand(tabID: String) {
        runningProcesses.remove(tabID)?.destroy()
        runningJobs.remove(tabID)?.cancel()
        updateTerminalTab(tabID) { it.copy(status = TerminalStatus.Cancelled, lines = it.lines + "Cancelled.") }
    }

    fun runAction(action: ActionSpec, context: RenderContext) {
        if (!externalProcessesEnabled) {
            val tab = TerminalTab.command(action.title, action.title).copy(
                status = TerminalStatus.Failed,
                lines = listOf("Command execution is not supported on this platform."),
            )
            _state.update {
                it.copy(
                    terminalTabs = it.terminalTabs + tab,
                    selectedTerminalTabID = tab.id,
                    terminalVisible = true,
                )
            }
            return
        }
        val command = renderCommand(action.command, context)
        val tab = TerminalTab.command(action.title, command.display)
        _state.update {
            it.copy(
                terminalTabs = it.terminalTabs + tab,
                selectedTerminalTabID = tab.id,
                terminalVisible = true,
            )
        }
        val job = scope.launch(Dispatchers.IO) {
            try {
                val process = ProcessBuilder(listOf(command.executable, *command.arguments.toTypedArray()))
                    .directory(command.workingDirectory?.let(::File) ?: File(context.bundleRootPath))
                    .redirectErrorStream(true)
                    .apply {
                        environment().putAll(command.environment)
                        environment()["GUI_FOR_CLI_BUNDLE_ROOT"] = context.bundleRootPath
                        environment()["GUI_FOR_CLI_BUNDLE_WORKSPACE"] = context.bundleRootPath
                    }
                    .start()
                runningProcesses[tab.id] = process
                process.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach { line -> updateTerminalTab(tab.id) { it.copy(lines = it.lines + line) } }
                }
                val exitCode = process.waitFor()
                val status = when (exitCode) {
                    0 -> TerminalStatus.Success
                    130 -> TerminalStatus.Cancelled
                    else -> TerminalStatus.Failed
                }
                updateTerminalTab(tab.id) {
                    it.copy(status = status, exitCode = exitCode, lines = it.lines + "Exited with code $exitCode.")
                }
                refreshDataSources()
            } catch (_: CancellationException) {
                updateTerminalTab(tab.id) {
                    it.copy(status = TerminalStatus.Cancelled, lines = it.lines + "Cancelled.")
                }
            } catch (error: Exception) {
                updateTerminalTab(tab.id) {
                    it.copy(
                        status = TerminalStatus.Failed,
                        lines = it.lines + "Could not start command: ${error.message}",
                    )
                }
            } finally {
                runningProcesses.remove(tab.id)
                runningJobs.remove(tab.id)
            }
        }
        runningJobs[tab.id] = job
    }

    fun renderContext(rowValues: Map<String, String> = emptyMap()): RenderContext {
        val snapshot = _state.value
        return RenderContext(
            bundleRootPath = snapshot.bundleRootPath,
            fieldValues = snapshot.fieldValues,
            checkedOptions = snapshot.checkedOptions.mapValues { (_, values) -> values.sorted().joinToString(",") },
            configValues = snapshot.configValues + snapshot.fieldValues,
            dataValues = snapshot.dataValues,
            rowValues = rowValues,
        )
    }

    fun effectiveControl(control: ControlSpec): ControlSpec {
        val payload = _state.value.dataPayloads[control.id] ?: return control
        return control.copy(
            options = payload.options ?: control.options,
            rows = payload.rows ?: control.rows,
            rowActions = payload.rowActions ?: control.rowActions,
        )
    }

    private fun installSession(session: BundleSession) {
        val manifest = session.manifest
        _state.update {
            it.copy(
                loading = false,
                manifest = manifest,
                iconMap = session.iconMap,
                bundleRootPath = session.bundleRoot.path,
                selectedPageID = if (selectInitialPage) {
                    manifest.pages.firstOrNull { page -> page.id != "settings" }?.id ?: manifest.pages.firstOrNull()?.id
                } else {
                    null
                },
                fieldValues = initialFieldValues(manifest),
                checkedOptions = initialCheckedOptions(manifest),
                configValues = initialConfigValues(manifest),
                terminalTabs = listOf(
                    TerminalTab.main().copy(lines = listOf("Loaded ${manifest.displayName} from ${session.bundleRoot.path}")),
                ),
            )
        }
        refreshDataSources()
    }

    private fun refreshDataSources() {
        val snapshot = _state.value
        val page = snapshot.selectedPage ?: return
        val refreshVersion = dataSourceRefreshVersion.incrementAndGet()
        val bundleRoot = File(snapshot.bundleRootPath)
        val runner = DataSourceRunner(bundleRoot)
        for ((id, dataSource, section) in dataSourcesFor(page)) {
            if (!externalProcessesEnabled) {
                _state.update {
                    it.copy(
                        dataPayloads = it.dataPayloads + (id to DataSourcePayload()),
                        loadingDataSources = it.loadingDataSources - id,
                        dataSourceErrors = it.dataSourceErrors - id,
                    )
                }
                continue
            }
            _state.update {
                it.copy(
                    loadingDataSources = it.loadingDataSources + id,
                    dataSourceErrors = it.dataSourceErrors - id,
                )
            }
            scope.launch {
                runCatching { runner.load(dataSource, renderContext()) }
                    .onSuccess { payload ->
                        if (refreshVersion != dataSourceRefreshVersion.get()) {
                            return@onSuccess
                        }
                        _state.update {
                            it.copy(
                                dataPayloads = it.dataPayloads + (id to payload),
                                dataValues = it.dataValues + payload.values.orEmpty(),
                                loadingDataSources = it.loadingDataSources - id,
                            )
                        }
                    }
                    .onFailure { error ->
                        if (refreshVersion != dataSourceRefreshVersion.get()) {
                            return@onFailure
                        }
                        val label = section?.title ?: id
                        _state.update {
                            it.copy(
                                loadingDataSources = it.loadingDataSources - id,
                                dataSourceErrors = it.dataSourceErrors + (id to "Could not load $label: ${error.message}"),
                            )
                        }
                    }
            }
        }
    }

    private fun dataSourcesFor(page: BundlePage): List<Triple<String, dev.guiforcli.compose.model.DataSourceSpec, PageSection?>> =
        buildList {
            for (section in page.sections) {
                section.dataSource?.let { add(Triple(section.id, it, section)) }
                for (control in section.controls) {
                    control.dataSource?.let { add(Triple(control.id, it, section)) }
                }
            }
        }

    private fun updateTerminalTab(tabID: String, update: (TerminalTab) -> TerminalTab) {
        _state.update { state ->
            state.copy(terminalTabs = state.terminalTabs.map { if (it.id == tabID) update(it) else it })
        }
    }

    private fun initialFieldValues(manifest: BundleManifest): Map<String, String> =
        allControls(manifest)
            .filter { it.kind in setOf("text", "path", "dropdown", "toggle") }
            .associate { it.id to it.value.orEmpty() }

    private fun initialCheckedOptions(manifest: BundleManifest): Map<String, Set<String>> =
        allControls(manifest)
            .filter { it.kind == "checkboxGroup" }
            .associate { control -> control.id to control.options.filter { it.selected }.map { it.id }.toSet() }

    private fun initialConfigValues(manifest: BundleManifest): Map<String, String> =
        allControls(manifest)
            .filter { it.kind == "configEditor" }
            .flatMap { control ->
                control.settings.flatMap { setting ->
                    listOf(
                        "${control.id}.${setting.id}" to setting.value.orEmpty(),
                        setting.id to setting.value.orEmpty(),
                        setting.key to setting.value.orEmpty(),
                    )
                }
            }
            .toMap()

    private fun allControls(manifest: BundleManifest): List<ControlSpec> =
        manifest.pages.flatMap { page -> page.sections.flatMap { section -> section.controls } }
}
