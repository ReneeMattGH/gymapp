package com.gymapp.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.gymapp.android.data.remote.AccountUser
import com.gymapp.android.data.remote.PendingVerificationState
import com.gymapp.android.store.FormaUiState
import com.gymapp.android.store.FormaViewModel
import com.gymapp.android.ui.components.ErrorBanner
import com.gymapp.android.ui.components.FormaCard
import com.gymapp.android.ui.components.FormaConfirmDialog
import com.gymapp.android.ui.components.FormaChip
import com.gymapp.android.ui.components.FormaDivider
import com.gymapp.android.ui.components.FormaIcon
import com.gymapp.android.ui.components.FormaTextField
import com.gymapp.android.ui.components.KeyValueRow
import com.gymapp.android.ui.components.NoticeBanner
import com.gymapp.android.ui.components.Overline
import com.gymapp.android.ui.components.PageHeading
import com.gymapp.android.ui.components.PrimaryButton
import com.gymapp.android.ui.components.SecondaryButton
import com.gymapp.android.ui.components.SectionHeader
import com.gymapp.android.ui.components.SubScreenHeader
import com.gymapp.android.ui.components.TagLabel
import com.gymapp.android.ui.components.TextButton
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Radius
import com.gymapp.android.ui.theme.Spacing
import com.gymapp.android.ui.theme.bodyFont
import com.gymapp.android.ui.theme.displayFont
import kotlinx.coroutines.delay
import kotlin.math.ceil

private enum class AccountMode(val title: String) {
    SIGN_IN("Sign in"),
    CREATE("Create account"),
}

@Composable
fun AccountScreen(
    model: FormaViewModel,
    state: FormaUiState,
    onBack: () -> Unit,
) {
    val colors = FormaTheme.colors

    var mode by remember { mutableStateOf(AccountMode.SIGN_IN) }
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var forgotPassword by remember { mutableStateOf(false) }
    var currentPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var resetPassword by remember { mutableStateOf("") }
    var confirmResetPassword by remember { mutableStateOf("") }
    var deletePassword by remember { mutableStateOf("") }
    var confirmingDelete by remember { mutableStateOf(false) }
    var confirmingSignOut by remember { mutableStateOf(false) }
    var didAttemptSubmit by remember { mutableStateOf(false) }

    val isEmailValid = email.trim().let { it.contains("@") && it.contains(".") && !it.endsWith(".") }
    val nameProblem = if (mode == AccountMode.CREATE && name.trim().isEmpty()) "Enter the name members will see." else null
    val emailProblem = when {
        email.trim().isEmpty() -> "Enter your email address."
        !isEmailValid -> "Enter a valid email address."
        else -> null
    }
    val passwordProblem = when {
        password.isEmpty() -> "Enter your password."
        mode == AccountMode.CREATE && password.length < 10 -> "Use at least 10 characters."
        else -> null
    }

    fun start(operation: (done: (String?) -> Unit) -> Unit, onSuccess: () -> Unit = {}) {
        if (busy) return
        busy = true
        error = null
        operation { message ->
            busy = false
            if (message != null) error = message else onSuccess()
        }
    }

    fun submit() {
        didAttemptSubmit = true
        if (listOfNotNull(nameProblem, emailProblem, passwordProblem).isNotEmpty()) {
            error = "Check the highlighted fields and try again."
            return
        }
        start(
            operation = { done ->
                if (mode == AccountMode.CREATE) {
                    model.register(name.trim(), email.trim(), password, done)
                } else {
                    model.signIn(email.trim(), password, done)
                }
            },
            onSuccess = {
                password = ""
                didAttemptSubmit = false
            },
        )
    }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            SubScreenHeader(onBack = onBack)
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = Spacing.xl)
                    .padding(top = Spacing.sm, bottom = Spacing.xxxl),
                verticalArrangement = Arrangement.spacedBy(Spacing.xl),
            ) {
                if (state.pendingVerification == null) {
                    PageHeading(
                        eyebrow = "Account",
                        title = "Forma account.",
                        subtitle = "Optional. An account connects Community and sync across devices. Your training profile stays on this device either way.",
                    )
                }
                state.accountNotice?.let { NoticeBanner(message = it, icon = "checkmark.circle", accent = true) }
                error?.let { ErrorBanner(message = it) }

                when {
                    !state.accountConfigured -> UnavailableCard()

                    state.pendingVerification != null -> OtpCard(
                        model = model,
                        pending = state.pendingVerification!!,
                        onChangeEmail = {
                            model.cancelPendingVerification()
                            error = null
                        },
                    )

                    state.pendingResetToken != null -> {
                        val token = state.pendingResetToken!!
                        FormaCard {
                            Overline(text = "New password")
                            Text(
                                "This link came from Forma. Choose a new password for your account.",
                                style = bodyFont(12.5f),
                                color = colors.textSecondary,
                            )
                            FormaTextField(
                                value = resetPassword,
                                onValueChange = { resetPassword = it },
                                placeholder = "At least 10 characters",
                                label = "New password",
                                secure = true,
                                capitalization = KeyboardCapitalization.None,
                            )
                            FormaTextField(
                                value = confirmResetPassword,
                                onValueChange = { confirmResetPassword = it },
                                placeholder = "Repeat the new password",
                                label = "Confirm password",
                                secure = true,
                                capitalization = KeyboardCapitalization.None,
                                isInvalid = confirmResetPassword.isNotEmpty() && confirmResetPassword != resetPassword,
                                message = if (confirmResetPassword.isEmpty() || confirmResetPassword == resetPassword) {
                                    null
                                } else {
                                    "Passwords do not match."
                                },
                            )
                            PrimaryButton(
                                title = "Set new password",
                                icon = "lock.rotation",
                                isLoading = busy,
                                isDisabled = resetPassword.length < 10 || resetPassword != confirmResetPassword,
                                onClick = {
                                    start(
                                        operation = { done -> model.confirmPasswordReset(token, resetPassword, done) },
                                        onSuccess = {
                                            resetPassword = ""
                                            confirmResetPassword = ""
                                        },
                                    )
                                },
                            )
                            TextButton(title = "Cancel") { model.setPendingResetToken(null) }
                        }
                    }

                    state.account != null -> {
                        SignedInCard(model = model, account = state.account!!, busy = busy)
                        SecurityCard(
                            colors = colors,
                            currentPassword = currentPassword,
                            newPassword = newPassword,
                            confirmPassword = confirmPassword,
                            busy = busy,
                            onCurrent = { currentPassword = it },
                            onNew = { newPassword = it },
                            onConfirm = { confirmPassword = it },
                            onSubmit = {
                                start(
                                    operation = { done -> model.changePassword(currentPassword, newPassword, done) },
                                    onSuccess = {
                                        currentPassword = ""
                                        newPassword = ""
                                        confirmPassword = ""
                                    },
                                )
                            },
                        )
                        SecondaryButton(
                            title = "Sign out",
                            icon = "rectangle.portrait.and.arrow.right",
                            isDisabled = busy,
                            onClick = { confirmingSignOut = true },
                        )
                        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                            SectionHeader(title = "Delete account")
                            FormaCard {
                                Text(
                                    "Deleting the account removes ${state.account!!.email} from the backend and signs out every device. Local training data on this device is not touched.",
                                    style = bodyFont(12.5f),
                                    color = colors.textSecondary,
                                )
                                if (confirmingDelete) {
                                    FormaTextField(
                                        value = deletePassword,
                                        onValueChange = { deletePassword = it },
                                        placeholder = "Account password",
                                        label = "Confirm with your password",
                                        secure = true,
                                        capitalization = KeyboardCapitalization.None,
                                    )
                                    PrimaryButton(
                                        title = "Delete account permanently",
                                        icon = "trash",
                                        isLoading = busy,
                                        isDisabled = deletePassword.isEmpty(),
                                        onClick = {
                                            start(
                                                operation = { done -> model.deleteAccount(deletePassword, done) },
                                                onSuccess = {
                                                    deletePassword = ""
                                                    confirmingDelete = false
                                                },
                                            )
                                        },
                                    )
                                    TextButton(title = "Keep account") {
                                        confirmingDelete = false
                                        deletePassword = ""
                                    }
                                } else {
                                    SecondaryButton(
                                        title = "Delete account",
                                        icon = "trash",
                                        destructive = true,
                                        onClick = {
                                            confirmingDelete = true
                                            error = null
                                        },
                                    )
                                }
                            }
                        }
                    }

                    else -> {
                        // Signed out
                        Column(verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                                AccountMode.entries.forEach { item ->
                                    FormaChip(
                                        label = item.title,
                                        selected = mode == item,
                                        onClick = {
                                            if (mode == item) return@FormaChip
                                            mode = item
                                            error = null
                                            didAttemptSubmit = false
                                            model.clearAccountMessages()
                                            model.clearNotice()
                                        },
                                    )
                                }
                            }

                            FormaCard {
                                if (mode == AccountMode.CREATE) {
                                    FormaTextField(
                                        value = name,
                                        onValueChange = { name = it },
                                        placeholder = "How members see you",
                                        label = "Display name",
                                        capitalization = KeyboardCapitalization.Words,
                                        isInvalid = didAttemptSubmit && nameProblem != null,
                                        message = if (didAttemptSubmit) nameProblem else null,
                                    )
                                }
                                FormaTextField(
                                    value = email,
                                    onValueChange = { email = it },
                                    placeholder = "you@example.com",
                                    label = "Email",
                                    keyboardType = KeyboardType.Email,
                                    capitalization = KeyboardCapitalization.None,
                                    isInvalid = didAttemptSubmit && emailProblem != null,
                                    message = if (didAttemptSubmit) emailProblem else null,
                                )
                                FormaTextField(
                                    value = password,
                                    onValueChange = { password = it },
                                    placeholder = if (mode == AccountMode.SIGN_IN) "Your password" else "At least 10 characters",
                                    label = "Password",
                                    secure = true,
                                    capitalization = KeyboardCapitalization.None,
                                    isInvalid = didAttemptSubmit && passwordProblem != null,
                                    message = if (didAttemptSubmit) passwordProblem else null,
                                    imeAction = ImeAction.Done,
                                    onSubmit = { submit() },
                                )
                                PrimaryButton(
                                    title = mode.title,
                                    icon = if (mode == AccountMode.SIGN_IN) "arrow.right.circle" else "person.badge.plus",
                                    isLoading = busy,
                                    isDisabled = busy,
                                    onClick = { submit() },
                                )
                            }

                            if (mode == AccountMode.SIGN_IN) {
                                TextButton(
                                    title = if (forgotPassword) "Hide password reset" else "Forgot password?",
                                ) {
                                    forgotPassword = !forgotPassword
                                    error = null
                                }
                                if (forgotPassword) {
                                    FormaCard {
                                        Overline(text = "Reset password")
                                        Text(
                                            "We will email a reset link if this address has an account. The backend sends it through its configured mail service — no message is faked.",
                                            style = bodyFont(12.5f),
                                            color = colors.textSecondary,
                                        )
                                        FormaTextField(
                                            value = email,
                                            onValueChange = { email = it },
                                            placeholder = "you@example.com",
                                            label = "Email",
                                            keyboardType = KeyboardType.Email,
                                            capitalization = KeyboardCapitalization.None,
                                        )
                                        PrimaryButton(
                                            title = "Send reset link",
                                            icon = "paperplane",
                                            isLoading = busy,
                                            isDisabled = !isEmailValid,
                                            onClick = {
                                                start(
                                                    operation = { done -> model.requestPasswordReset(email, done) },
                                                    onSuccess = { forgotPassword = false },
                                                )
                                            },
                                        )
                                    }
                                }
                            }

                            NoticeBanner(
                                message = "Your local training data never moves to the server. Signing in only adds an account for Community and sync.",
                                icon = "internaldrive",
                            )
                        }
                    }
                }
            }
        }
    }

    if (confirmingSignOut) {
        FormaConfirmDialog(
            title = "Sign out of this account?",
            message = "Your training data stays on this device.",
            confirmLabel = "Sign out",
            destructive = true,
            onConfirm = {
                confirmingSignOut = false
                busy = true
                model.signOut { busy = false }
            },
            onDismiss = { confirmingSignOut = false },
        )
    }
}

@Composable
private fun UnavailableCard() {
    val colors = FormaTheme.colors
    FormaCard(style = com.gymapp.android.ui.components.CardStyle.RAISED) {
        FormaIcon("network.slash", size = 28.dp, tint = colors.accentText)
        Text("Accounts need the Forma backend", style = displayFont(18f, FontWeight.SemiBold), color = colors.text)
        Text(
            "This build has no backend URL, so there is nothing to sign in to. The app is fully usable without an account: plans, workouts, check-ins and reminders are stored in the on-device database.",
            style = bodyFont(13f),
            color = colors.textSecondary,
        )
    }
}

@Composable
private fun SignedInCard(model: FormaViewModel, account: AccountUser, busy: Boolean) {
    val colors = FormaTheme.colors
    FormaCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Overline(text = "Signed in")
            Spacer(Modifier.weight(1f))
            TagLabel(
                text = if (account.emailVerified) "Verified" else "Unverified",
                color = if (account.emailVerified) colors.accentText else colors.warning,
            )
        }
        Text(account.email, style = displayFont(19f, FontWeight.SemiBold), color = colors.text)
        KeyValueRow(label = "Account ID", value = account.id.take(8))
        if (!account.emailVerified) {
            FormaDivider()
            NoticeBanner(
                message = "Confirm your email so Community can trust this account and you can recover it.",
                icon = "envelope.badge",
            )
            SecondaryButton(
                title = "Enter verification code",
                icon = "number.square",
                isDisabled = busy,
                onClick = { model.beginVerification(account.email) },
            )
        }
    }
}

@Composable
private fun SecurityCard(
    colors: com.gymapp.android.ui.theme.FormaColors,
    currentPassword: String,
    newPassword: String,
    confirmPassword: String,
    busy: Boolean,
    onCurrent: (String) -> Unit,
    onNew: (String) -> Unit,
    onConfirm: (String) -> Unit,
    onSubmit: () -> Unit,
) {
    FormaCard {
        Overline(text = "Password")
        FormaTextField(
            value = currentPassword,
            onValueChange = onCurrent,
            placeholder = "Your current password",
            label = "Current password",
            secure = true,
            capitalization = KeyboardCapitalization.None,
        )
        FormaTextField(
            value = newPassword,
            onValueChange = onNew,
            placeholder = "At least 10 characters",
            label = "New password",
            secure = true,
            capitalization = KeyboardCapitalization.None,
        )
        FormaTextField(
            value = confirmPassword,
            onValueChange = onConfirm,
            placeholder = "Repeat the new password",
            label = "Confirm new password",
            secure = true,
            capitalization = KeyboardCapitalization.None,
            isInvalid = confirmPassword.isNotEmpty() && confirmPassword != newPassword,
            message = if (confirmPassword.isEmpty() || confirmPassword == newPassword) null else "Passwords do not match.",
        )
        PrimaryButton(
            title = "Update password",
            icon = "lock",
            isLoading = busy,
            isDisabled = currentPassword.isEmpty() || newPassword.length < 10 || newPassword != confirmPassword,
            onClick = onSubmit,
        )
    }
}

// MARK: - Email verification

@Composable
private fun OtpCard(
    model: FormaViewModel,
    pending: PendingVerificationState,
    onChangeEmail: () -> Unit,
) {
    val colors = FormaTheme.colors
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var resending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        while (true) {
            delay(1000)
            now = System.currentTimeMillis()
        }
    }
    LaunchedEffect(Unit) {
        delay(350)
        runCatching { focusRequester.requestFocus() }
    }

    fun verify() {
        if (code.length != 6 || busy) return
        busy = true
        error = null
        notice = null
        model.verifyOtp(code) { message ->
            busy = false
            if (message != null) {
                error = message
                if (message.contains("expired", ignoreCase = true) || message.contains("incorrect", ignoreCase = true)) {
                    code = ""
                }
            }
        }
    }

    fun resend() {
        if (resending || busy) return
        resending = true
        error = null
        notice = null
        model.resendOtp { message ->
            resending = false
            if (message != null) {
                error = message
            } else {
                code = ""
                notice = "A new six-digit code was sent."
            }
        }
    }

    val seconds = maxOf(0, ceil((pending.resendAvailableAt - now) / 1000.0).toInt())

    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        PageHeading(
            eyebrow = "Verify email",
            title = "Check your inbox.",
            subtitle = "Enter the six-digit code we sent to ${maskedEmail(pending.email)}. It works once and expires in ten minutes.",
        )
        FormaCard(style = com.gymapp.android.ui.components.CardStyle.RAISED) {
            Overline(text = "Six-digit code")
            OtpCodeField(
                code = code,
                onCodeChange = { code = it },
                focusRequester = focusRequester,
                onSubmit = { verify() },
            )
            error?.let { ErrorBanner(message = it) }
            notice?.let { NoticeBanner(message = it, icon = "envelope.badge", accent = true) }
            PrimaryButton(
                title = "Verify email",
                icon = "checkmark.shield",
                isLoading = busy,
                isDisabled = code.length != 6 || busy || resending,
                onClick = { verify() },
            )
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = Spacing.xs),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                when {
                    seconds > 0 -> {
                        FormaIcon("clock", size = 12.dp, tint = colors.textTertiary)
                        Text(
                            "Resend available in ${seconds}s",
                            style = bodyFont(12.5f),
                            color = colors.textSecondary,
                        )
                    }
                    resending -> {
                        androidx.compose.material3.CircularProgressIndicator(
                            Modifier.size(14.dp),
                            color = colors.accentText,
                            strokeWidth = 2.dp,
                        )
                        Text("Sending a new code…", style = bodyFont(12.5f), color = colors.textSecondary)
                    }
                    else -> TextButton(title = "Resend code") { resend() }
                }
                Spacer(Modifier.weight(1f))
            }
            FormaDivider()
            TextButton(title = "Use a different email") { onChangeEmail() }
        }
        NoticeBanner(
            message = "The code is checked by the Forma backend. The app never treats a registration as complete until that check succeeds.",
            icon = "lock.shield",
        )
    }
}

@Composable
private fun OtpCodeField(
    code: String,
    onCodeChange: (String) -> Unit,
    focusRequester: FocusRequester,
    onSubmit: () -> Unit,
) {
    val colors = FormaTheme.colors
    Box(Modifier.fillMaxWidth()) {
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            (0..5).forEach { index ->
                val filled = index < code.length
                val active = index == minOf(code.length, 5)
                Box(
                    Modifier
                        .weight(1f)
                        .height(56.dp)
                        .clip(RoundedCornerShape(Radius.sm))
                        .background(colors.input)
                        .border(
                            width = if (active) 1.5.dp else 1.dp,
                            color = if (active) colors.accentBorder else colors.border,
                            shape = RoundedCornerShape(Radius.sm),
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        if (filled) code[index].toString() else "",
                        style = TextStyle(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 24.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                        color = colors.text,
                    )
                }
            }
        }
        BasicTextField(
            value = code,
            onValueChange = { raw -> onCodeChange(raw.filter { it.isDigit() }.take(6)) },
            textStyle = TextStyle(color = Color.Transparent, fontSize = 1.sp),
            cursorBrush = SolidColor(Color.Transparent),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { onSubmit() }),
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp)
                .focusRequester(focusRequester),
        )
    }
}

private fun maskedEmail(email: String): String {
    val at = email.indexOf('@')
    if (at <= 0) return email
    val name = email.substring(0, at)
    val domain = email.substring(at + 1)
    val visible = if (name.length > 2) name.take(2) else name.take(1)
    return "$visible${"•".repeat(maxOf(2, name.length - visible.length))}@$domain"
}
