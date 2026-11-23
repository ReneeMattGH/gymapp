import SwiftUI

/// The remote Forma account, kept deliberately separate from the on-device
/// training profile. Signing in never moves, merges or rewrites local data.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn
        case createAccount

        var id: String { rawValue }
        var title: String { self == .signIn ? "Sign in" : "Create account" }
    }

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var forgotPassword = false
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var resetPassword = ""
    @State private var confirmResetPassword = ""
    @State private var deletePassword = ""
    @State private var confirmingDelete = false
    @State private var resendNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                PageHeading(
                    eyebrow: "Account",
                    title: "Forma account.",
                    subtitle: "Optional. An account connects Community and sync across devices. Your training profile stays on this device either way."
                )
                if let notice = model.accountNotice {
                    NoticeBanner(message: notice, systemImage: "checkmark.circle", accent: true)
                }
                if let error {
                    ErrorBanner(message: error)
                }
                if !model.isAccountAvailable {
                    unavailableCard
                } else if let token = model.pendingPasswordResetToken {
                    resetCard(token: token)
                } else if let account = model.remoteAccount {
                    signedInCard(account)
                    securityCard
                    signOutCard
                    dangerZone(account)
                } else {
                    signedOutCard
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxl)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(FormaBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Backend missing

    private var unavailableCard: some View {
        FormaCard(style: .raised) {
            Image(systemName: "network.slash")
                .font(.system(size: 28))
                .foregroundStyle(palette.accentText)
            Text("Accounts need the Forma backend")
                .font(FormaFont.displayFont(18, weight: .semibold))
                .foregroundStyle(palette.text)
            Text("This build has no backend URL, so there is nothing to sign in to. The app is fully usable without an account: plans, workouts, check-ins and reminders are stored in the on-device database.")
                .font(FormaFont.bodyFont(13))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Signed out

    private var signedOutCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                ForEach(Mode.allCases) { item in
                    FormaChip(label: item.title, selected: mode == item) {
                        guard mode != item else { return }
                        mode = item
                        error = nil
                    }
                }
            }

            FormaCard {
                if mode == .createAccount {
                    FormaTextField(
                        label: "Display name",
                        placeholder: "How members see you",
                        text: $name,
                        capitalization: .words,
                        contentType: .name
                    )
                }
                FormaTextField(
                    label: "Email",
                    placeholder: "you@example.com",
                    text: $email,
                    keyboard: .emailAddress,
                    capitalization: .never,
                    contentType: .username
                )
                FormaTextField(
                    label: "Password",
                    placeholder: mode == .signIn ? "Your password" : "At least 10 characters",
                    text: $password,
                    secure: true,
                    capitalization: .never,
                    contentType: mode == .signIn ? .password : nil
                )
                PrimaryButton(
                    title: mode.title,
                    systemImage: mode == .signIn ? "arrow.right.circle" : "person.badge.plus",
                    isLoading: busy,
                    isDisabled: !canSubmit
                ) {
                    submit()
                }
            }

            if mode == .signIn {
                TextButton(title: forgotPassword ? "Hide password reset" : "Forgot password?") {
                    forgotPassword.toggle()
                    error = nil
                }
                if forgotPassword {
                    forgotCard
                }
            }

            NoticeBanner(
                message: "Your local training data never moves to the server. Signing in only adds an account for Community and sync.",
                systemImage: "internaldrive"
            )
        }
    }

    private var forgotCard: some View {
        FormaCard {
            Overline(text: "Reset password")
            Text("We will email a reset link if this address has an account. The backend sends it through its configured mail service — no message is faked.")
                .font(FormaFont.bodyFont(12.5))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            FormaTextField(
                label: "Email",
                placeholder: "you@example.com",
                text: $email,
                keyboard: .emailAddress,
                capitalization: .never,
                contentType: .username
            )
            PrimaryButton(
                title: "Send reset link",
                systemImage: "paperplane",
                isLoading: busy,
                isDisabled: !isEmailValid
            ) {
                run {
                    try await model.requestAccountPasswordReset(email: email)
                    forgotPassword = false
                }
            }
        }
    }

    // MARK: - Reset token

    private func resetCard(token: String) -> some View {
        FormaCard {
            Overline(text: "New password")
            Text("This link came from Forma. Choose a new password for your account.")
                .font(FormaFont.bodyFont(12.5))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            FormaTextField(
                label: "New password",
                placeholder: "At least 10 characters",
                text: $resetPassword,
                secure: true,
                capitalization: .never,
                contentType: .newPassword
            )
            FormaTextField(
                label: "Confirm password",
                placeholder: "Repeat the new password",
                text: $confirmResetPassword,
                secure: true,
                capitalization: .never,
                contentType: .newPassword
            )
            PrimaryButton(
                title: "Set new password",
                systemImage: "lock.rotation",
                isLoading: busy,
                isDisabled: resetPassword.count < 10 || resetPassword != confirmResetPassword
            ) {
                run {
                    try await model.confirmAccountPasswordReset(token: token, password: resetPassword)
                    resetPassword = ""
                    confirmResetPassword = ""
                }
            }
            TextButton(title: "Cancel") {
                model.pendingPasswordResetToken = nil
            }
        }
    }

    // MARK: - Signed in

    private func signedInCard(_ account: AppUser) -> some View {
        FormaCard {
            HStack {
                Overline(text: "Signed in")
                Spacer()
                TagLabel(
                    text: account.emailVerified ? "Verified" : "Unverified",
                    color: account.emailVerified ? palette.accentText : palette.warning
                )
            }
            Text(account.email ?? "—")
                .font(FormaFont.displayFont(19, weight: .semibold))
                .foregroundStyle(palette.text)
            KeyValueRow(label: "Account ID", value: String(account.id.prefix(8)))
            if !account.emailVerified {
                FormaDivider()
                NoticeBanner(
                    message: "Confirm your email so your account can be recovered and Community stays trustworthy.",
                    systemImage: "envelope.badge"
                )
                if let resendNotice {
                    Text(resendNotice)
                        .font(FormaFont.bodyFont(12))
                        .foregroundStyle(palette.textSecondary)
                }
                SecondaryButton(title: "Resend confirmation email", systemImage: "paperplane", isDisabled: busy) {
                    run {
                        let sent = try await model.resendVerificationEmail()
                        resendNotice = sent
                            ? "The backend sent a new confirmation email."
                            : "This email is already confirmed."
                    }
                }
            }
        }
    }

    private var securityCard: some View {
        FormaCard {
            Overline(text: "Password")
            FormaTextField(
                label: "Current password",
                placeholder: "Your current password",
                text: $currentPassword,
                secure: true,
                capitalization: .never,
                contentType: .password
            )
            FormaTextField(
                label: "New password",
                placeholder: "At least 10 characters",
                text: $newPassword,
                secure: true,
                capitalization: .never,
                contentType: .newPassword
            )
            FormaTextField(
                label: "Confirm new password",
                placeholder: "Repeat the new password",
                text: $confirmPassword,
                secure: true,
                capitalization: .never,
                contentType: .newPassword
            )
            PrimaryButton(
                title: "Update password",
                systemImage: "lock",
                isLoading: busy,
                isDisabled: currentPassword.isEmpty || newPassword.count < 10 || newPassword != confirmPassword
            ) {
                run {
                    try await model.changeAccountPassword(current: currentPassword, new: newPassword)
                    currentPassword = ""
                    newPassword = ""
                    confirmPassword = ""
                }
            }
        }
    }

    private var signOutCard: some View {
        SecondaryButton(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
            Task {
                busy = true
                await model.signOutAccount()
                busy = false
            }
        }
    }

    private func dangerZone(_ account: AppUser) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Delete account")
            FormaCard {
                Text("Deleting the account removes \(account.email ?? "this account") from the backend and signs out every device. Local training data on this device is not touched.")
                    .font(FormaFont.bodyFont(12.5))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if confirmingDelete {
                    FormaTextField(
                        label: "Confirm with your password",
                        placeholder: "Account password",
                        text: $deletePassword,
                        secure: true,
                        capitalization: .never,
                        contentType: .password
                    )
                    PrimaryButton(
                        title: "Delete account permanently",
                        systemImage: "trash",
                        isLoading: busy,
                        isDisabled: deletePassword.isEmpty
                    ) {
                        run {
                            try await model.deleteRemoteAccount(password: deletePassword)
                            deletePassword = ""
                            confirmingDelete = false
                        }
                    }
                    TextButton(title: "Keep account") {
                        confirmingDelete = false
                        deletePassword = ""
                    }
                } else {
                    SecondaryButton(title: "Delete account", systemImage: "trash", destructive: true) {
                        confirmingDelete = true
                        error = nil
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var isEmailValid: Bool {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.contains("@") && value.contains(".") && !value.hasSuffix(".")
    }

    private var canSubmit: Bool {
        guard isEmailValid else { return false }
        if mode == .createAccount {
            return password.count >= 10 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !password.isEmpty
    }

    private func submit() {
        guard canSubmit else {
            error = mode == .createAccount
                ? "Check the name, email and that the password has at least 10 characters."
                : "Enter a valid email and your password."
            return
        }
        run {
            if mode == .createAccount {
                _ = try await model.createAccount(name: name, email: email, password: password)
            } else {
                try await model.signInAccount(email: email, password: password)
            }
            password = ""
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await operation()
                Haptics.success()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
