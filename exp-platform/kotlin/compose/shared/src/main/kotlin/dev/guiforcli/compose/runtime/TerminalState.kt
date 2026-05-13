package dev.guiforcli.compose.runtime

import java.util.UUID

enum class TerminalStatus { Idle, Running, Success, Warning, Failed, Cancelled }

data class TerminalTab(
    val id: String,
    val title: String,
    val commandDisplay: String? = null,
    val lines: List<String> = emptyList(),
    val status: TerminalStatus = TerminalStatus.Idle,
    val exitCode: Int? = null,
    val dismissible: Boolean = false,
) {
    companion object {
        const val MainTabID = "main"

        fun main(): TerminalTab = TerminalTab(
            id = MainTabID,
            title = "General",
            lines = listOf("Android Compose renderer starting."),
        )

        fun command(title: String, commandDisplay: String): TerminalTab = TerminalTab(
            id = UUID.randomUUID().toString(),
            title = title,
            commandDisplay = commandDisplay,
            lines = listOf("$ $commandDisplay"),
            status = TerminalStatus.Running,
            dismissible = true,
        )
    }
}
