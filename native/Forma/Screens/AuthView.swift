import SwiftUI

private enum AuthMode: String, CaseIterable {
    case signIn = "Sign in"
    case create = "Create account"
}

struct AuthView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @State private var mode: AuthMode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var notice: String?
    @State private var showReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    BrandMark(size: 50, color: palette.accent)
                        .padding(.bottom, Spacing.md)
                    Text("Train with intention.")
                        .font(FormaFont.displayFont(34, weight: .bold))
                        .foregroundStyle(palette.text)
                    Text("Forma builds a plan around your equipment, schedule, and experience — then tracks every session and connects you with your gym community.")
                        .font(FormaFont.bodyFont(14))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                authModePicker

                VStack(spacing: Spacing.md) {
                    if mode == .create {
                        FormaTextField(
                            label: "Name",
                            placeholder: "What should we call you?",
                            text: $name,
                            capitalization: .words,
                            contentType: .name
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    FormaTextField(
                        label: "Email",
                        placeholder: "you@example.com",
                        text: $email,
                        keyboard: .emailAddress,
                        capitalization: .never,
                        contentType: .emailAddress
                    )
                    FormaTextField(
                        label: "Password",
                        placeholder: mode == .signIn ? "Your password" : "At least 6 characters",
                        text: $password,
                        secure: true,
                        contentType: mode == .signIn ? .password : .newPassword
                    )
                }

                if let error = model.authError {
                    ErrorBanner(message: error)
                }
                if let notice {
                    NoticeBanner(message: notice, systemImage: "envelope", accent: true)
                }

                VStack(spacing: Spacing.md) {
                    PrimaryButton(
                        title: mode == .signIn ? "Sign in" : "Create account",
                        isLoading: model.authBusy,
                        isDisabled: !canSubmit
                    ) {
                        submit()
                    }
                    if mode == .signIn {
                        TextButton(title: "Forgot your password?") {
                            showReset = true
                        }
                    }
                }

                FormaCard(style: .raised) {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(palette.accentText)
                            .font(.system(size: 15))
                        Text("Your account and training data live in your Supabase project, protected by row-level security. Forma never stores a service-role key in the app.")
                            .font(FormaFont.bodyFont(12))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("Forma offers general fitness guidance, not medical advice. Stop if you feel pain, dizziness, or chest discomfort and seek professional help.")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xxxl)
            .padding(.bottom, Spacing.huge)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FormaBackground())
        .sheet(isPresented: $showReset) {
            ResetPasswordView(initialEmail: email)
        }
        .animation(.snappy(duration: 0.25), value: mode)
    }

    private var authModePicker: some View {
        HStack(spacing: 4) {
            ForEach(AuthMode.allCases, id: \.self) { option in
                Button {
                    Haptics.selection()
                    withAnimation(.snappy(duration: 0.22)) {
                        mode = option
                        notice = nil
                        model.authError = nil
                    }
                } label: {
                    Text(option.rawValue)
                        .font(FormaFont.bodyFont(13, weight: .medium))
                        .foregroundStyle(mode == option ? palette.accentInk : palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(mode == option ? AnyShapeStyle(palette.accent) : AnyShapeStyle(Color.clear), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(palette.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(palette.border, lineWidth: 1) }
    }

    private var canSubmit: Bool {
        let validEmail = email.contains("@") && email.contains(".")
        let validPassword = password.count >= 6
        if mode == .create {
            return validEmail && validPassword && name.trimmingCharacters(in: .whitespaces).count >= 2
        }
        return validEmail && validPassword
    }

    private func submit() {
        guard canSubmit else { return }
        notice = nil
        Task {
            if mode == .signIn {
                _ = await model.signIn(email: email, password: password)
            } else {
                if let outcome = await model.signUp(
                    name: name.trimmingCharacters(in: .whitespaces),
                    email: email,
                    password: password
                ) {
                    notice = outcome.message
                }
            }
        }
    }
}

struct ResetPasswordView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.formaPalette) private var palette
    @State private var email: String
    @State private var message: String?
    @State private var busy = false

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    SheetHeading(
                        title: "Reset your password",
                        subtitle: "We'll email a secure link. Open it on this device to set a new password."
                    )
                    FormaTextField(
                        label: "Email",
                        placeholder: "you@example.com",
                        text: $email,
                        keyboard: .emailAddress,
                        capitalization: .never,
                        contentType: .emailAddress
                    )
                    if let error = model.authError {
                        ErrorBanner(message: error)
                    }
                    if let message {
                        NoticeBanner(message: message, systemImage: "envelope", accent: true)
                    }
                    PrimaryButton(title: "Send reset link", isLoading: busy, isDisabled: !email.contains("@")) {
                        busy = true
                        Task {
                            message = await model.resetPassword(email: email)
                            busy = false
                        }
                    }
                }
                .padding(Spacing.xl)
            }
            .background(FormaBackground())
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct UpdatePasswordView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.formaPalette) private var palette
    @State private var password = ""
    @State private var confirm = ""
    @State private var done = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    SheetHeading(
                        title: done ? "Password updated" : "Set a new password",
                        subtitle: done
                            ? "You can sign in with the new password from now on."
                            : "Choose a new password for your Forma account."
                    )
                    if done {
                        NoticeBanner(message: "Your password was updated.", systemImage: "checkmark.circle", accent: true)
                        PrimaryButton(title: "Done") { dismiss() }
                    } else {
                        FormaTextField(label: "New password", placeholder: "At least 6 characters", text: $password, secure: true, contentType: .newPassword)
                        FormaTextField(label: "Confirm password", placeholder: "Repeat it", text: $confirm, secure: true, contentType: .newPassword)
                        if let error = model.authError {
                            ErrorBanner(message: error)
                        }
                        let valid = password.count >= 6 && password == confirm
                        PrimaryButton(title: "Update password", isLoading: model.authBusy, isDisabled: !valid) {
                            Task {
                                done = await model.updatePassword(password)
                            }
                        }
                    }
                }
                .padding(Spacing.xl)
            }
            .background(FormaBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }
}
