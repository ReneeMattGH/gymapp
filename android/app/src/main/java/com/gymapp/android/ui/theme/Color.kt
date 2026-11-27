package com.gymapp.android.ui.theme

import androidx.compose.ui.graphics.Color

/** Exact Forma brand values ported from the iOS palette. */
object FormaBrand {
    val Lime = Color(0xFFC7FA4F)
    val Ink = Color(0xFF070806)
    val GradientStart = Color(0xFFD8FF76)
    val GradientEnd = Color(0xFFAEEB3E)
}

data class FormaColors(
    val background: Color,
    val backgroundAlt: Color,
    val surface: Color,
    val surfaceRaised: Color,
    val border: Color,
    val borderStrong: Color,
    val text: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val accent: Color,
    val accentInk: Color,
    val accentText: Color,
    val accentSoft: Color,
    val accentBorder: Color,
    val danger: Color,
    val dangerSoft: Color,
    val warning: Color,
    val warningSoft: Color,
    val info: Color,
    val success: Color,
    val input: Color,
    val isDark: Boolean,
)

val DarkColors = FormaColors(
    background = Color(0xFF070806),
    backgroundAlt = Color(0xFF0A0C09),
    surface = Color(0xFF10130E),
    surfaceRaised = Color(0xFF171B14),
    border = Color(0x14E8FFC8),
    borderStrong = Color(0x29E8FFC8),
    text = Color(0xFFF3F6EE),
    textSecondary = Color(0xFFA9B2A0),
    textTertiary = Color(0xFF6F7869),
    accent = FormaBrand.Lime,
    accentInk = Color(0xFF0B0E06),
    accentText = Color(0xFFC7FA4F),
    accentSoft = Color(0x1FC7FA4F),
    accentBorder = Color(0x5CC7FA4F),
    danger = Color(0xFFFF7A6B),
    dangerSoft = Color(0x1FFF7A6B),
    warning = Color(0xFFF2C46B),
    warningSoft = Color(0x1FF2C46B),
    info = Color(0xFF8DCBFF),
    success = Color(0xFFC7FA4F),
    input = Color(0xFF12160F),
    isDark = true,
)

val LightColors = FormaColors(
    background = Color(0xFFF3F4EC),
    backgroundAlt = Color(0xFFEAEDE0),
    surface = Color(0xFFFFFFFF),
    surfaceRaised = Color(0xFFF7F8F1),
    border = Color(0x1F101408),
    borderStrong = Color(0x38101408),
    text = Color(0xFF101408),
    textSecondary = Color(0xFF575F4D),
    textTertiary = Color(0xFF8A9280),
    accent = FormaBrand.Lime,
    accentInk = Color(0xFF101408),
    accentText = Color(0xFF4F6E00),
    accentSoft = Color(0x1A60840A),
    accentBorder = Color(0x524F6E00),
    danger = Color(0xFFBE4535),
    dangerSoft = Color(0x1ABE4535),
    warning = Color(0xFF946200),
    warningSoft = Color(0x1A946200),
    info = Color(0xFF276C99),
    success = Color(0xFF4F6E00),
    input = Color(0xFFF2F4EC),
    isDark = false,
)
