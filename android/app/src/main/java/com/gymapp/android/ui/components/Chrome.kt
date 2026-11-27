package com.gymapp.android.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Spacing
import com.gymapp.android.ui.theme.bodyFont
import com.gymapp.android.ui.theme.displayFont

/** Custom back chrome used instead of a Material TopAppBar to keep the Forma identity. */
@Composable
fun SubScreenHeader(
    title: String? = null,
    subtitle: String? = null,
    onBack: () -> Unit,
    trailing: (@Composable () -> Unit)? = null,
) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(horizontal = Spacing.xl, vertical = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Box(
            Modifier
                .size(36.dp)
                .formaClickable(onClick = onBack),
            contentAlignment = Alignment.Center,
        ) {
            FormaIcon("chevron.left", size = 19.dp, tint = colors.text)
        }
        if (title != null) {
            Column(Modifier.weight(1f)) {
                Text(
                    title,
                    style = displayFont(17f, androidx.compose.ui.text.font.FontWeight.SemiBold),
                    color = colors.text,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (subtitle != null) {
                    Text(
                        subtitle,
                        style = bodyFont(11f),
                        color = colors.textTertiary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        } else {
            Spacer(Modifier.weight(1f))
        }
        trailing?.invoke()
    }
}
