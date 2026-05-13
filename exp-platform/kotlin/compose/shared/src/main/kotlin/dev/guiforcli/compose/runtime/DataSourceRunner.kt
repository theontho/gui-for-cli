package dev.guiforcli.compose.runtime

import dev.guiforcli.compose.model.DataSourcePayload
import dev.guiforcli.compose.model.DataSourceSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

class DataSourceRunner(private val bundleRoot: File, private val timeoutSeconds: Long = 15) {
    suspend fun load(dataSource: DataSourceSpec, context: RenderContext): DataSourcePayload =
        withContext(Dispatchers.IO) {
            val executable = requireInsideBundle(File(bundleRoot, interpolate(dataSource.path, context)), "data source executable")
            val arguments = dataSource.arguments.map { interpolate(it, context) }
            val workingDirectory = dataSource.workingDirectory
                ?.let { requireInsideBundle(File(resolveUserPath(interpolate(it, context), bundleRoot.path)), "data source working directory") }
                ?: bundleRoot.canonicalFile
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
            val outputReader = CompletableFuture.supplyAsync {
                process.inputStream.bufferedReader().readText()
            }
            val finished = process.waitFor(timeoutSeconds, TimeUnit.SECONDS)
            if (!finished) {
                process.destroy()
                if (!process.waitFor(2, TimeUnit.SECONDS)) {
                    process.destroyForcibly()
                }
                val output = outputReader.getNow("")
                error("Data source ${dataSource.path} timed out after ${timeoutSeconds}s:\n$output")
            }
            val output = outputReader.get(2, TimeUnit.SECONDS)
            val exitCode = process.exitValue()
            if (exitCode != 0) {
                error("Data source ${dataSource.path} exited with $exitCode:\n$output")
            }
            parseDataSourcePayload(JSONObject(output))
        }

    private fun requireInsideBundle(candidate: File, label: String): File {
        val rootPath = bundleRoot.canonicalFile.toPath().normalize()
        val candidateFile = candidate.canonicalFile
        val candidatePath = candidateFile.toPath().normalize()
        require(candidatePath.startsWith(rootPath)) {
            "$label must stay inside bundle root: $candidate"
        }
        return candidateFile
    }
}
