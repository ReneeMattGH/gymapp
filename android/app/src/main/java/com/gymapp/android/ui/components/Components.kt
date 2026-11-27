package com.gymapp.android.ui.components

import android.os.Build
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gymapp.android.domain.Exercise
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Radius
import com.gymapp.android.ui.theme.Spacing
import com.gymapp.android.ui.theme.bodyFont
import com.gymapp.android.ui.theme.displayFont
import com.gymapp.android.ui.theme.formaAccentBrush

// MARK: - Backgrounds

@Composable
fun FormaBackground(modifier: Modifier = Modifier) {
    val colors = FormaTheme.colors
    Box(modifier.fillMaxSize().background(Brush.verticalGradient(listOf(colors.background, colors.backgroundAlt)))) {
        val blurSupported = Build.VERSION.SDK_INT >= 31
        Box(
            Modifier
                .align(Alignment.TopEnd)
                .padding(top = 0.dp)
                .size(380.dp)
                .offset(x = 140.dp, y = (-300).dp)
                .then(if (blurSupported) Modifier.blur(90.dp) else Modifier)
                .background(colors.accent.copy(alpha = 0.07f), CircleShape),
        )
        Box(
            Modifier
                .align(Alignment.BottomStart)
                .size(300.dp)
                .offset(x = (-180).dp, y = 420.dp)
                .then(if (blurSupported) Modifier.blur(100.dp) else Modifier)
                .background(colors.accent.copy(alpha = 0.035f), CircleShape),
        )
    }
}

// MARK: - Press feedback

@Composable
fun Modifier.formaClickable(enabled: Boolean = true, onClick: () -> Unit): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.98f else 1f, tween(160), label = "press")
    return this
        .scale(scale)
        .clickable(
            interactionSource = interaction,
            indication = null,
            enabled = enabled,
            onClick = onClick,
        )
}

// MARK: - Surfaces

enum class CardStyle { STANDARD, RAISED, ACCENT }

@Composable
fun FormaCard(
    modifier: Modifier = Modifier,
    style: CardStyle = CardStyle.STANDARD,
    padding: Dp = Spacing.lg,
    content: @Composable () -> Unit,
) {
    val colors = FormaTheme.colors
    val background = when (style) {
        CardStyle.STANDARD -> colors.surface
        CardStyle.RAISED -> colors.surfaceRaised
        CardStyle.ACCENT -> colors.accentSoft
    }
    val border = if (style == CardStyle.ACCENT) colors.accentBorder else colors.border
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.lg))
            .background(background)
            .border(1.dp, border, RoundedCornerShape(Radius.lg))
            .padding(padding),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        content()
    }
}

@Composable
fun SectionHeader(title: String, actionLabel: String? = null, onAction: (() -> Unit)? = null) {
    val colors = FormaTheme.colors
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Text(
            title.uppercase(),
            style = bodyFont(11f, FontWeight.SemiBold).copy(letterSpacing = 1.4.sp),
            color = colors.textSecondary,
        )
        Spacer(Modifier.weight(1f))
        if (actionLabel != null && onAction != null) {
            Text(
                actionLabel,
                style = bodyFont(13f, FontWeight.Medium),
                color = colors.accentText,
                modifier = Modifier.formaClickable(onClick = onAction),
            )
        }
    }
}

@Composable
fun Overline(text: String) {
    Text(
        text.uppercase(),
        style = bodyFont(11f, FontWeight.SemiBold).copy(letterSpacing = 1.6.sp),
        color = FormaTheme.colors.accentText,
    )
}

@Composable
fun PageHeading(eyebrow: String? = null, title: String, subtitle: String? = null) {
    val colors = FormaTheme.colors
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        if (eyebrow != null) Overline(eyebrow)
        Text(title, style = displayFont(30f, FontWeight.Bold), color = colors.text)
        if (subtitle != null) {
            Text(subtitle, style = bodyFont(14f), color = colors.textSecondary)
        }
    }
}

// MARK: - Brand

@Composable
fun BrandMark(size: Dp = 58.dp, color: Color = FormaTheme.colors.accentText) {
    Canvas(Modifier.size(size)) {
        val w = this.size.width
        val h = this.size.height
        val bar = w * 0.16f
        val gap = w * 0.10f
        // Three ascending bars forming the Forma mark.
        drawRoundRect(
            color = color,
            topLeft = Offset(0f, h * 0.55f),
            size = Size(bar, h * 0.45f),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(bar / 2f),
        )
        drawRoundRect(
            color = color,
            topLeft = Offset(bar + gap, h * 0.28f),
            size = Size(bar, h * 0.72f),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(bar / 2f),
        )
        drawRoundRect(
            color = color.copy(alpha = 0.75f),
            topLeft = Offset((bar + gap) * 2f, h * 0.06f),
            size = Size(bar, h * 0.94f),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(bar / 2f),
        )
    }
}

@Composable
fun Wordmark(compact: Boolean = false) {
    val colors = FormaTheme.colors
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        BrandMark(size = if (compact) 22.dp else 26.dp)
        Text(
            "FORMA",
            style = displayFont(if (compact) 13f else 15f, FontWeight.Bold).copy(letterSpacing = 3.sp),
            color = colors.text,
        )
    }
}

// MARK: - Buttons

@Composable
fun PrimaryButton(
    title: String,
    modifier: Modifier = Modifier,
    icon: String? = null,
    isLoading: Boolean = false,
    isDisabled: Boolean = false,
    onClick: () -> Unit,
) {
    val colors = FormaTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 50.dp)
            .clip(RoundedCornerShape(Radius.md))
            .background(formaAccentBrush())
            .formaClickable(enabled = !isDisabled && !isLoading, onClick = onClick)
            .padding(horizontal = Spacing.lg),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val contentAlpha = if (isDisabled) 0.45f else 1f
        if (isLoading) {
            CircularProgressIndicator(Modifier.size(18.dp), color = colors.accentInk, strokeWidth = 2.dp)
        } else if (icon != null) {
            FormaIcon(icon, size = 16.dp, tint = colors.accentInk.copy(alpha = contentAlpha))
        }
        if (isLoading || icon != null) Spacer(Modifier.width(Spacing.sm))
        Text(
            title,
            style = bodyFont(15f, FontWeight.SemiBold),
            color = colors.accentInk.copy(alpha = contentAlpha),
        )
    }
}

@Composable
fun SecondaryButton(
    title: String,
    modifier: Modifier = Modifier,
    icon: String? = null,
    isDisabled: Boolean = false,
    destructive: Boolean = false,
    onClick: () -> Unit,
) {
    val colors = FormaTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 46.dp)
            .clip(RoundedCornerShape(Radius.md))
            .background(colors.surface)
            .border(1.dp, if (destructive) colors.danger.copy(alpha = 0.3f) else colors.border, RoundedCornerShape(Radius.md))
            .formaClickable(enabled = !isDisabled, onClick = onClick)
            .padding(horizontal = Spacing.lg),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val tint = if (destructive) colors.danger else colors.text
        val alpha = if (isDisabled) 0.45f else 1f
        if (icon != null) {
            FormaIcon(icon, size = 15.dp, tint = tint.copy(alpha = alpha))
            Spacer(Modifier.width(Spacing.sm))
        }
        Text(title, style = bodyFont(14f, FontWeight.Medium), color = tint.copy(alpha = alpha))
    }
}

@Composable
fun IconButton(
    icon: String,
    label: String,
    accent: Boolean = false,
    onClick: () -> Unit,
) {
    val colors = FormaTheme.colors
    Box(
        Modifier
            .size(44.dp)
            .clip(CircleShape)
            .then(
                if (accent) Modifier.background(formaAccentBrush())
                else Modifier.background(colors.surface).border(1.dp, colors.border, CircleShape),
            )
            .formaClickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        FormaIcon(icon, size = 16.dp, tint = if (accent) colors.accentInk else colors.text)
    }
}

@Composable
fun TextButton(title: String, destructive: Boolean = false, onClick: () -> Unit) {
    Text(
        title,
        style = bodyFont(13f, FontWeight.Medium),
        color = if (destructive) FormaTheme.colors.danger else FormaTheme.colors.accentText,
        modifier = Modifier.formaClickable(onClick = onClick),
    )
}

// MARK: - Chips

@Composable
fun FormaChip(
    label: String,
    selected: Boolean = false,
    disabled: Boolean = false,
    onClick: () -> Unit,
) {
    val colors = FormaTheme.colors
    Box(
        Modifier
            .clip(CircleShape)
            .background(if (selected) colors.accent else colors.surface)
            .border(1.dp, if (selected) Color.Transparent else colors.border, CircleShape)
            .formaClickable(enabled = !disabled, onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = 9.dp),
    ) {
        Text(
            label,
            style = bodyFont(13f, FontWeight.Medium),
            color = if (selected) colors.accentInk else colors.textSecondary,
        )
    }
}

@Composable
fun TagLabel(text: String, color: Color? = null) {
    val tint = color ?: FormaTheme.colors.accentText
    Text(
        text.uppercase(),
        style = bodyFont(10f, FontWeight.SemiBold).copy(letterSpacing = 0.8.sp),
        color = tint,
        modifier = Modifier
            .clip(CircleShape)
            .background(tint.copy(alpha = 0.12f))
            .padding(horizontal = 8.dp, vertical = 4.dp),
    )
}

// MARK: - Inputs

@Composable
fun FormaTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    label: String? = null,
    secure: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
    suffix: String? = null,
    isInvalid: Boolean = false,
    message: String? = null,
    imeAction: ImeAction = ImeAction.Next,
    enabled: Boolean = true,
    onSubmit: (() -> Unit)? = null,
) {
    val colors = FormaTheme.colors
    var focused by remember { mutableStateOf(false) }
    var revealed by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (label != null) {
            Text(label, style = bodyFont(12f, FontWeight.Medium), color = colors.textSecondary)
        }
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clip(RoundedCornerShape(Radius.sm))
                .background(colors.input)
                .border(
                    1.dp,
                    if (isInvalid) colors.danger else if (focused) colors.accentBorder else colors.border,
                    RoundedCornerShape(Radius.sm),
                )
                .padding(start = Spacing.md, end = if (secure) Spacing.xs else Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.weight(1f)) {
                if (value.isEmpty()) {
                    Text(placeholder, style = bodyFont(15f), color = colors.textTertiary)
                }
                BasicTextField(
                    value = value,
                    onValueChange = onValueChange,
                    enabled = enabled,
                    textStyle = bodyFont(15f).copy(color = colors.text),
                    cursorBrush = SolidColor(colors.accentText),
                    singleLine = true,
                    visualTransformation = if (secure && !revealed) PasswordVisualTransformation() else VisualTransformation.None,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = keyboardType,
                        capitalization = capitalization,
                        imeAction = imeAction,
                    ),
                    keyboardActions = KeyboardActions(onDone = { onSubmit?.invoke() }),
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 24.dp)
                        .onFocusChanged { focused = it.isFocused },
                )
            }
            if (secure) {
                Box(
                    Modifier
                        .size(44.dp)
                        .formaClickable { revealed = !revealed },
                    contentAlignment = Alignment.Center,
                ) {
                    FormaIcon(if (revealed) "eye.slash" else "eye", size = 16.dp, tint = colors.textSecondary)
                }
            } else if (suffix != null) {
                Text(suffix, style = bodyFont(12f), color = colors.textTertiary)
            }
        }
        if (message != null) {
            Text(message, style = bodyFont(11.5f), color = colors.danger)
        }
    }
}

@Composable
fun FormaTextEditor(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    placeholder: String,
    modifier: Modifier = Modifier,
    minHeight: Dp = 96.dp,
) {
    val colors = FormaTheme.colors
    var focused by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, style = bodyFont(12f, FontWeight.Medium), color = colors.textSecondary)
        Box(
            Modifier
                .fillMaxWidth()
                .heightIn(min = minHeight)
                .clip(RoundedCornerShape(Radius.sm))
                .background(colors.input)
                .border(1.dp, if (focused) colors.accentBorder else colors.border, RoundedCornerShape(Radius.sm))
                .padding(Spacing.md),
        ) {
            if (value.isEmpty()) {
                Text(placeholder, style = bodyFont(14f), color = colors.textTertiary)
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                textStyle = bodyFont(14f).copy(color = colors.text),
                cursorBrush = SolidColor(colors.accentText),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = minHeight - 24.dp)
                    .onFocusChanged { focused = it.isFocused },
            )
        }
    }
}

@Composable
fun StepperControl(value: Int, range: IntRange, suffix: String? = null, onChange: (Int) -> Unit) {
    val colors = FormaTheme.colors
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        StepperButton("minus", enabled = value > range.first) { onChange((value - 1).coerceAtLeast(range.first)) }
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.widthIn(min = 56.dp)) {
            Text("$value", style = displayFont(22f, FontWeight.SemiBold), color = colors.text)
            if (suffix != null) Text(suffix, style = bodyFont(10f, FontWeight.Medium), color = colors.textTertiary)
        }
        StepperButton("plus", enabled = value < range.last) { onChange((value + 1).coerceAtMost(range.last)) }
    }
}

@Composable
private fun StepperButton(icon: String, enabled: Boolean, onClick: () -> Unit) {
    val colors = FormaTheme.colors
    Box(
        Modifier
            .size(40.dp)
            .clip(CircleShape)
            .background(colors.surfaceRaised)
            .border(1.dp, colors.border, CircleShape)
            .formaClickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        FormaIcon(icon, size = 15.dp, tint = if (enabled) colors.text else colors.textTertiary)
    }
}

@Composable
fun FormaToggle(checked: Boolean, onCheckedChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val colors = FormaTheme.colors
    Switch(
        checked = checked,
        onCheckedChange = onCheckedChange,
        modifier = modifier,
        colors = SwitchDefaults.colors(
            checkedThumbColor = colors.accentInk,
            checkedTrackColor = colors.accent,
            uncheckedThumbColor = colors.textSecondary,
            uncheckedTrackColor = colors.surfaceRaised,
            uncheckedBorderColor = colors.border,
        ),
    )
}

// MARK: - Feedback

@Composable
fun ErrorBanner(message: String, retry: (() -> Unit)? = null) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.sm))
            .background(colors.dangerSoft)
            .border(1.dp, colors.danger.copy(alpha = 0.22f), RoundedCornerShape(Radius.sm))
            .padding(Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        FormaIcon("exclamationmark.triangle.fill", size = 14.dp, tint = colors.danger)
        Text(message, style = bodyFont(13f), color = colors.text, modifier = Modifier.weight(1f))
        if (retry != null) {
            Text(
                "Retry",
                style = bodyFont(12f, FontWeight.SemiBold),
                color = colors.accentText,
                modifier = Modifier.formaClickable(onClick = retry),
            )
        }
    }
}

@Composable
fun NoticeBanner(message: String, icon: String = "info.circle", accent: Boolean = false) {
    val colors = FormaTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.sm))
            .background(if (accent) colors.accentSoft else colors.surfaceRaised)
            .border(1.dp, if (accent) colors.accentBorder else colors.border, RoundedCornerShape(Radius.sm))
            .padding(Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        FormaIcon(icon, size = 14.dp, tint = if (accent) colors.accentText else colors.textSecondary)
        Text(
            message,
            style = bodyFont(13f),
            color = if (accent) colors.textSecondary else colors.textSecondary,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
fun FormaEmptyState(
    icon: String,
    title: String,
    message: String,
    actionTitle: String? = null,
    onAction: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val colors = FormaTheme.colors
    Column(
        modifier
            .fillMaxWidth()
            .padding(vertical = Spacing.xxl, horizontal = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Box(
            Modifier.size(58.dp).clip(CircleShape).background(colors.accentSoft),
            contentAlignment = Alignment.Center,
        ) {
            FormaIcon(icon, size = 27.dp, tint = colors.accentText)
        }
        Text(title, style = displayFont(19f, FontWeight.SemiBold), color = colors.text, textAlign = TextAlign.Center)
        Text(message, style = bodyFont(13f), color = colors.textSecondary, textAlign = TextAlign.Center)
        if (actionTitle != null && onAction != null) {
            Text(
                actionTitle,
                style = bodyFont(13f, FontWeight.SemiBold),
                color = colors.accentInk,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(colors.accent)
                    .formaClickable(onClick = onAction)
                    .padding(horizontal = Spacing.lg, vertical = 10.dp),
            )
        }
    }
}

@Composable
fun LoadingCard(label: String = "Loading") {
    val colors = FormaTheme.colors
    Row(
        Modifier.fillMaxWidth().padding(vertical = Spacing.xxl),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircularProgressIndicator(Modifier.size(18.dp), color = colors.accentText, strokeWidth = 2.dp)
        Spacer(Modifier.width(Spacing.md))
        Text(label, style = bodyFont(13f), color = colors.textSecondary)
    }
}

@Composable
fun SkeletonBlock(height: Dp = 14.dp, width: Dp? = null, corner: Dp = Radius.sm) {
    val colors = FormaTheme.colors
    val transition = rememberInfiniteTransition(label = "skeleton")
    val alpha by transition.animateFloat(
        initialValue = 1f,
        targetValue = 0.55f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "skeletonAlpha",
    )
    Box(
        Modifier
            .then(if (width != null) Modifier.width(width) else Modifier.fillMaxWidth())
            .height(height)
            .clip(RoundedCornerShape(corner))
            .background(colors.surfaceRaised.copy(alpha = alpha)),
    )
}

// MARK: - Data display

@Composable
fun StatTile(value: String, label: String, detail: String? = null, accent: Boolean = false, modifier: Modifier = Modifier) {
    val colors = FormaTheme.colors
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.md))
            .background(colors.surface)
            .border(1.dp, if (accent) colors.accentBorder else colors.border, RoundedCornerShape(Radius.md))
            .padding(Spacing.md),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            value,
            style = displayFont(24f, FontWeight.Bold),
            color = if (accent) colors.accentText else colors.text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            label.uppercase(),
            style = bodyFont(10f, FontWeight.SemiBold).copy(letterSpacing = 1.sp),
            color = colors.textTertiary,
        )
        if (detail != null) Text(detail, style = bodyFont(11f), color = colors.textSecondary)
    }
}

@Composable
fun ProgressRing(
    progress: Double,
    size: Dp = 92.dp,
    lineWidth: Dp = 9.dp,
    label: String? = null,
    caption: String? = null,
) {
    val colors = FormaTheme.colors
    val animated by animateFloatAsState(
        targetValue = progress.coerceIn(0.001, 1.0).toFloat(),
        animationSpec = tween(600),
        label = "ring",
    )
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = lineWidth.toPx()
            val inset = stroke / 2f
            drawArc(
                color = colors.surfaceRaised,
                startAngle = 0f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = Offset(inset, inset),
                size = Size(this.size.width - stroke, this.size.height - stroke),
                style = Stroke(width = stroke),
            )
            drawArc(
                brush = Brush.sweepGradient(listOf(colors.accentText.copy(alpha = 0.7f), colors.accentText)),
                startAngle = -90f,
                sweepAngle = 360f * animated,
                useCenter = false,
                topLeft = Offset(inset, inset),
                size = Size(this.size.width - stroke, this.size.height - stroke),
                style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            if (label != null) {
                Text(
                    label,
                    style = displayFont((size.value * 0.22f), FontWeight.Bold),
                    color = colors.text,
                )
            }
            if (caption != null) {
                Text(
                    caption.uppercase(),
                    style = bodyFont(8f, FontWeight.SemiBold).copy(letterSpacing = 0.6.sp),
                    color = colors.textTertiary,
                )
            }
        }
    }
}

@Composable
fun SetDots(total: Int, completed: Int) {
    val colors = FormaTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        repeat(maxOf(total, 1)) { index ->
            val done = index < completed
            Box(
                Modifier
                    .height(6.dp)
                    .width(if (done) 18.dp else 10.dp)
                    .clip(CircleShape)
                    .background(if (done) colors.accentText else colors.surfaceRaised)
                    .then(if (!done) Modifier.border(1.dp, colors.border, CircleShape) else Modifier)
                    .animateContentSize(),
            )
        }
    }
}

@Composable
fun KeyValueRow(label: String, value: String, valueColor: Color? = null) {
    val colors = FormaTheme.colors
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = bodyFont(13f), color = colors.textSecondary)
        Spacer(Modifier.weight(1f))
        Text(value, style = bodyFont(13f, FontWeight.Medium), color = valueColor ?: colors.text, textAlign = TextAlign.End)
    }
}

@Composable
fun FormaDivider() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(FormaTheme.colors.border))
}

// MARK: - Sheet chrome

@Composable
fun SheetHeading(title: String, subtitle: String? = null, onClose: (() -> Unit)? = null) {
    val colors = FormaTheme.colors
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = displayFont(22f, FontWeight.Bold), color = colors.text)
            if (subtitle != null) Text(subtitle, style = bodyFont(13f), color = colors.textSecondary)
        }
        if (onClose != null) {
            Box(
                Modifier
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(colors.surfaceRaised)
                    .formaClickable(onClick = onClose),
                contentAlignment = Alignment.Center,
            ) {
                FormaIcon("xmark", size = 13.dp, tint = colors.textSecondary)
            }
        }
    }
}

// MARK: - Exercise presentation

@Composable
fun MuscleTags(exercise: Exercise, limit: Int = 3) {
    val colors = FormaTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        exercise.primaryMuscles.take(limit).forEach { muscle ->
            Text(
                muscle.label,
                style = bodyFont(10f, FontWeight.Medium),
                color = colors.textSecondary,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(colors.surfaceRaised)
                    .padding(horizontal = 7.dp, vertical = 3.dp),
            )
        }
        if (exercise.primaryMuscles.size > limit) {
            Text(
                "+${exercise.primaryMuscles.size - limit}",
                style = bodyFont(10f, FontWeight.Medium),
                color = colors.textTertiary,
            )
        }
    }
}

@Composable
fun ExerciseGlyph(exercise: Exercise, size: Dp = 44.dp) {
    val colors = FormaTheme.colors
    Box(
        Modifier
            .size(size)
            .clip(RoundedCornerShape(size * 0.3f))
            .background(colors.accentSoft),
        contentAlignment = Alignment.Center,
    ) {
        FormaIcon(ExerciseIcons.symbol(exercise), size = size * 0.42f, tint = colors.accentText)
    }
}

object ExerciseIcons {
    fun symbol(exercise: Exercise): String = when (exercise.category) {
        com.gymapp.android.domain.ExerciseCategory.MOBILITY -> "figure.flexibility"
        com.gymapp.android.domain.ExerciseCategory.CONDITIONING -> "figure.run"
        com.gymapp.android.domain.ExerciseCategory.STRENGTH ->
            if (exercise.primaryGroups.any { it == com.gymapp.android.domain.MuscleGroup.BACK } ||
                exercise.primaryGroups.any { it == com.gymapp.android.domain.MuscleGroup.ARMS }
            ) {
                "figure.strengthtraining.functional"
            } else {
                "figure.strengthtraining.traditional"
            }
    }
}

// MARK: - Icons

/** Ports the SF Symbol names used by the iOS UI onto Material rounded icons. */
@Composable
fun FormaIcon(name: String, size: Dp = 16.dp, tint: Color = FormaTheme.colors.text) {
    Icon(FormaIcons.vector(name), contentDescription = null, tint = tint, modifier = Modifier.size(size))
}

object FormaIcons {
    fun vector(name: String): ImageVector = when (name) {
        "house" -> Icons.Rounded.Home
        "dumbbell", "figure.strengthtraining.traditional", "figure.strengthtraining.functional" -> Icons.Rounded.FitnessCenter
        "figure.run", "figure.mixed.cardio", "figure.highintensity.intervaltraining" -> Icons.Rounded.DirectionsRun
        "figure.flexibility" -> Icons.Rounded.SelfImprovement
        "figure.walk" -> Icons.Rounded.DirectionsWalk
        "figure.cooldown" -> Icons.Rounded.Spa
        "chart.line.uptrend.xyaxis" -> Icons.Rounded.ShowChart
        "chart.bar" -> Icons.Rounded.BarChart
        "calendar", "calendar.badge.clock" -> Icons.Rounded.CalendarMonth
        "person.2" -> Icons.Rounded.Groups
        "person.crop.circle" -> Icons.Rounded.AccountCircle
        "person.badge.plus" -> Icons.Rounded.PersonAdd
        "person.crop.circle.badge.checkmark" -> Icons.Rounded.VerifiedUser
        "bell" -> Icons.Rounded.Notifications
        "bell.badge" -> Icons.Rounded.NotificationsActive
        "heart", "heart.text.square" -> Icons.Rounded.FavoriteBorder
        "heart.fill" -> Icons.Rounded.Favorite
        "heart.slash" -> Icons.Rounded.HeartBroken
        "waveform.path.ecg" -> Icons.Rounded.MonitorHeart
        "plus" -> Icons.Rounded.Add
        "minus" -> Icons.Rounded.Remove
        "minus.circle" -> Icons.Rounded.RemoveCircleOutline
        "chevron.left" -> Icons.Rounded.ChevronLeft
        "chevron.right" -> Icons.Rounded.ChevronRight
        "chevron.up" -> Icons.Rounded.KeyboardArrowUp
        "chevron.down" -> Icons.Rounded.KeyboardArrowDown
        "xmark" -> Icons.Rounded.Close
        "checkmark" -> Icons.Rounded.Check
        "checkmark.circle", "checkmark.circle.fill" -> Icons.Rounded.CheckCircle
        "checkmark.seal" -> Icons.Rounded.Verified
        "checkmark.shield" -> Icons.Rounded.Security
        "exclamationmark.triangle", "exclamationmark.triangle.fill" -> Icons.Rounded.Warning
        "info.circle" -> Icons.Rounded.Info
        "clock" -> Icons.Rounded.Schedule
        "timer" -> Icons.Rounded.Timer
        "play.fill" -> Icons.Rounded.PlayArrow
        "pause.fill", "pause.circle" -> Icons.Rounded.Pause
        "flag.checkered" -> Icons.Rounded.SportsScore
        "trash" -> Icons.Rounded.Delete
        "ellipsis" -> Icons.Rounded.MoreHoriz
        "forward.end" -> Icons.Rounded.SkipNext
        "arrow.triangle.2.circlepath" -> Icons.Rounded.Sync
        "arrow.clockwise" -> Icons.Rounded.Refresh
        "arrow.right" -> Icons.Rounded.ArrowForward
        "arrow.right.circle" -> Icons.Rounded.ArrowCircleRight
        "arrow.up.right" -> Icons.Rounded.NorthEast
        "sparkles" -> Icons.Rounded.AutoAwesome
        "lock" -> Icons.Rounded.Lock
        "lock.shield" -> Icons.Rounded.Shield
        "lock.rotation" -> Icons.Rounded.LockReset
        "rectangle.portrait.and.arrow.right" -> Icons.Rounded.Logout
        "paperplane" -> Icons.Rounded.Send
        "envelope.badge" -> Icons.Rounded.MarkEmailUnread
        "number.square" -> Icons.Rounded.Pin
        "eye" -> Icons.Rounded.Visibility
        "eye.slash" -> Icons.Rounded.VisibilityOff
        "star" -> Icons.Rounded.StarBorder
        "star.fill" -> Icons.Rounded.Star
        "magnifyingglass" -> Icons.Rounded.Search
        "line.3.horizontal.decrease", "line.3.horizontal.decrease.circle.fill" -> Icons.Rounded.FilterList
        "slider.horizontal.3" -> Icons.Rounded.Tune
        "books.vertical" -> Icons.Rounded.MenuBook
        "list.number" -> Icons.Rounded.FormatListNumbered
        "list.bullet.clipboard" -> Icons.Rounded.Assignment
        "target" -> Icons.Rounded.GpsFixed
        "flame" -> Icons.Rounded.LocalFireDepartment
        "wind" -> Icons.Rounded.Air
        "moon.stars" -> Icons.Rounded.NightlightRound
        "moon" -> Icons.Rounded.DarkMode
        "sun.max" -> Icons.Rounded.LightMode
        "circle.lefthalf.filled" -> Icons.Rounded.Contrast
        "leaf" -> Icons.Rounded.Spa
        "bed.double" -> Icons.Rounded.Bedtime
        "drop" -> Icons.Rounded.WaterDrop
        "fork.knife" -> Icons.Rounded.Restaurant
        "building.2" -> Icons.Rounded.Business
        "mappin.and.ellipse" -> Icons.Rounded.Place
        "square.stack.3d.up" -> Icons.Rounded.Layers
        "camera.viewfinder" -> Icons.Rounded.CenterFocusStrong
        "camera.fill" -> Icons.Rounded.PhotoCamera
        "scalemass" -> Icons.Rounded.MonitorWeight
        "questionmark.circle" -> Icons.Rounded.HelpOutline
        "externaldrive.badge.exclamationmark" -> Icons.Rounded.Storage
        "network.slash" -> Icons.Rounded.CloudOff
        "wifi.exclamationmark", "wifi.slash" -> Icons.Rounded.WifiOff
        "internaldrive" -> Icons.Rounded.Smartphone
        "location.slash" -> Icons.Rounded.LocationOff
        "gearshape" -> Icons.Rounded.Settings
        "shield.lefthalf.filled" -> Icons.Rounded.Security
        "app.badge" -> Icons.Rounded.Apps
        else -> Icons.Rounded.Circle
    }
}

// MARK: - Small utilities

@Composable
fun ProfileAvatar(name: String, size: Dp = 40.dp, photo: android.graphics.Bitmap? = null, showCameraBadge: Boolean = false) {
    val colors = FormaTheme.colors
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .fillMaxSize()
                .clip(CircleShape)
                .background(colors.accent),
            contentAlignment = Alignment.Center,
        ) {
            if (photo != null) {
                androidx.compose.foundation.Image(
                    bitmap = photo.asImageBitmap(),
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                )
            } else {
                val initial = name.trim().firstOrNull()?.uppercaseChar() ?: 'F'
                Text(
                    initial.toString(),
                    style = displayFont(size.value * 0.4f, FontWeight.Bold),
                    color = colors.accentInk,
                )
            }
        }
        if (showCameraBadge) {
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .size(size * 0.32f)
                    .clip(CircleShape)
                    .background(colors.accent)
                    .border(2.dp, colors.background, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                FormaIcon("camera.fill", size = size * 0.16f, tint = colors.accentInk)
            }
        }
    }
}

// MARK: - Dialogs

@Composable
fun FormaConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String,
    cancelLabel: String = "Cancel",
    destructive: Boolean = false,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = FormaTheme.colors
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surfaceRaised,
        titleContentColor = colors.text,
        textContentColor = colors.textSecondary,
        title = { Text(title, style = displayFont(19f, FontWeight.SemiBold)) },
        text = { Text(message, style = bodyFont(13f)) },
        confirmButton = {
            androidx.compose.material3.TextButton(onClick = onConfirm) {
                Text(
                    confirmLabel,
                    color = if (destructive) colors.danger else colors.accentText,
                    style = bodyFont(14f, FontWeight.Medium),
                )
            }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) {
                Text(cancelLabel, color = colors.textSecondary, style = bodyFont(14f))
            }
        },
    )
}
