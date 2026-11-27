package com.gymapp.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.dp

object Spacing {
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 16.dp
    val xl = 20.dp
    val xxl = 24.dp
    val xxxl = 32.dp
    val huge = 48.dp
}

object Radius {
    val sm = 10.dp
    val md = 14.dp
    val lg = 20.dp
    val xl = 26.dp
    val xxl = 32.dp
}

val LocalFormaColors = compositionLocalOf { DarkColors }

object FormaTheme {
    val colors: FormaColors
        @Composable get() = LocalFormaColors.current
}

@Composable
fun FormaTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colors = if (darkTheme) DarkColors else LightColors
    val scheme = if (darkTheme) {
        darkColorScheme(
            primary = colors.accent,
            onPrimary = colors.accentInk,
            secondary = colors.accentText,
            background = colors.background,
            onBackground = colors.text,
            surface = colors.surface,
            onSurface = colors.text,
            surfaceVariant = colors.surfaceRaised,
            onSurfaceVariant = colors.textSecondary,
            outline = colors.border,
            error = colors.danger,
        )
    } else {
        lightColorScheme(
            primary = colors.accent,
            onPrimary = colors.accentInk,
            secondary = colors.accentText,
            background = colors.background,
            onBackground = colors.text,
            surface = colors.surface,
            onSurface = colors.text,
            surfaceVariant = colors.surfaceRaised,
            onSurfaceVariant = colors.textSecondary,
            outline = colors.border,
            error = colors.danger,
        )
    }
    CompositionLocalProvider(LocalFormaColors provides colors) {
        MaterialTheme(
            colorScheme = scheme,
            typography = FormaTypography,
            content = content,
        )
    }
}

@Composable
fun formaScreenBrush(): Brush {
    val colors = FormaTheme.colors
    return Brush.verticalGradient(listOf(colors.background, colors.backgroundAlt))
}

@Composable
fun formaAccentBrush(): Brush =
    Brush.linearGradient(listOf(FormaBrand.GradientStart, FormaBrand.GradientEnd))
