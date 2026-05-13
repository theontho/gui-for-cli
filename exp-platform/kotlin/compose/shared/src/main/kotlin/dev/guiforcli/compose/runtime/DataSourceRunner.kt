package dev.guiforcli.compose.runtime

import dev.guiforcli.compose.model.DataSourcePayload
import dev.guiforcli.compose.model.DataSourceSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

class DataSourceRunner(private val bundleRoot: File) {
    suspend fun load(dataSource: DataSourceSpec, context: RenderContext): DataSourcePayload =
        withContext(Dispatchers.IO) {
            val executable = File(bundleRoot, dataSource.path)
            val arguments = dataSource.arguments.map { interpolate(it, context) }
            val workingDirectory = dataSource.workingDirectory
                ?.let { File(resolveUserPath(interpolate(it, context), bundleRoot.path)) }
                ?: bundleRoot
            val process = ProcessBuilder(listOf(executable.path, *arguments.toTypedArray()))
                .directory(workingDirectory)
                .redirectErrorStream(true)
                .apply {
                    environment().putAll(dataSource.environment.mapValues { interpolate(it.value, context) })
                    environment()["GUI_FOR_CLI_BUNDLE_ROOT"] = bundleRoot.path
                    environment()["GUI_FOR_CLI_BUNDLE_WORKSPACE"] = bundleRoot.path
                    environment()["GUI_FOR_CLI_OFFLINE"] = "1"
                }
                .start()
            val output = process.inputStream.bufferedReader().readText()
            val exitCode = process.waitFor()
            if (exitCode != 0) {
                error("Data source ${dataSource.path} exited with $exitCode:\n$output")
            }
            parseDataSourcePayload(JSONObject(output))
        }
}
