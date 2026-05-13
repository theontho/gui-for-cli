package dev.guiforcli.compose.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign

private const val DefaultTextIcon = "•"

fun String?.resolvedTextIcon(): String = this?.takeIf { it.isNotBlank() } ?: DefaultTextIcon

@Composable
fun TextIcon(value: String?, modifier: Modifier = Modifier) {
    Text(
        value.resolvedTextIcon(),
        modifier = modifier,
        style = MaterialTheme.typography.titleMedium,
        textAlign = TextAlign.Center,
    )
}
