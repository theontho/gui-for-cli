package dev.guiforcli.compose.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import dev.guiforcli.compose.runtime.BundleIconMap

private const val DefaultTextIcon = "•"

fun String?.resolvedTextIcon(): String = this?.takeIf { it.isNotBlank() } ?: DefaultTextIcon

fun resolvedTextIcon(textIcon: String?, iconName: String?, iconMap: BundleIconMap): String =
    resolvedOptionalTextIcon(textIcon, iconName, iconMap) ?: DefaultTextIcon

fun resolvedOptionalTextIcon(textIcon: String?, iconName: String?, iconMap: BundleIconMap): String? =
    textIcon?.takeIf { it.isNotBlank() }
        ?: iconMap.resolving(iconName, source = BundleIconMap.EmojiSource)

@Composable
fun TextIcon(
    value: String?,
    modifier: Modifier = Modifier,
    iconName: String? = null,
    iconMap: BundleIconMap = BundleIconMap(),
) {
    Text(
        resolvedTextIcon(value, iconName, iconMap),
        modifier = modifier,
        style = MaterialTheme.typography.titleMedium,
        textAlign = TextAlign.Center,
    )
}
