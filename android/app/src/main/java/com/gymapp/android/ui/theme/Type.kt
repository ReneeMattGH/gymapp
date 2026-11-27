package com.gymapp.android.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import com.gymapp.android.R

val SpaceGrotesk = FontFamily(
    Font(R.font.space_grotesk_medium, FontWeight.Medium),
    Font(R.font.space_grotesk_semibold, FontWeight.SemiBold),
    Font(R.font.space_grotesk_bold, FontWeight.Bold),
)

val Inter = FontFamily(
    Font(R.font.inter_regular, FontWeight.Normal),
    Font(R.font.inter_medium, FontWeight.Medium),
    Font(R.font.inter_semibold, FontWeight.SemiBold),
)

fun displayFont(size: Float, weight: FontWeight = FontWeight.SemiBold, lineHeight: Float = size * 1.18f): TextStyle =
    TextStyle(fontFamily = SpaceGrotesk, fontWeight = weight, fontSize = size.sp, lineHeight = lineHeight.sp)

fun bodyFont(size: Float, weight: FontWeight = FontWeight.Normal, lineHeight: Float = size * 1.42f): TextStyle =
    TextStyle(fontFamily = Inter, fontWeight = weight, fontSize = size.sp, lineHeight = lineHeight.sp)

fun displayFont(size: TextUnit, weight: FontWeight = FontWeight.SemiBold): TextStyle =
    displayFont(size.value, weight)

fun bodyFont(size: TextUnit, weight: FontWeight = FontWeight.Normal): TextStyle =
    bodyFont(size.value, weight)

val FormaTypography = Typography(
    displayLarge = displayFont(34f, FontWeight.Bold),
    displayMedium = displayFont(30f, FontWeight.Bold),
    displaySmall = displayFont(27f, FontWeight.Bold),
    headlineLarge = displayFont(24f, FontWeight.Bold),
    headlineMedium = displayFont(22f, FontWeight.SemiBold),
    headlineSmall = displayFont(19f, FontWeight.SemiBold),
    titleLarge = displayFont(18f, FontWeight.SemiBold),
    titleMedium = bodyFont(16f, FontWeight.SemiBold),
    titleSmall = bodyFont(14f, FontWeight.SemiBold),
    bodyLarge = bodyFont(15f),
    bodyMedium = bodyFont(13f),
    bodySmall = bodyFont(11.5f),
    labelLarge = bodyFont(13f, FontWeight.SemiBold),
    labelMedium = bodyFont(11f, FontWeight.SemiBold),
    labelSmall = bodyFont(10f, FontWeight.Medium),
)
