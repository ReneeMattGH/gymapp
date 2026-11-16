import SwiftUI

struct SetupRequiredView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @State private var showPreviewConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                Wordmark()

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Overline(text: "Setup required")
                    Text("Connect your backend\nto go live.")
                        .font(FormaFont.displayFont(36, weight: .bold))
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The interface, plan engine, workout tracker, and coach are built. Authentication, sync, and live AI need your Supabase project — no keys are included in this build.")
                        .font(FormaFont.bodyFont(14))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                FormaCard {
                    Text("What is waiting on credentials")
                        .font(FormaFont.displayFont(17, weight: .semibold))
                        .foregroundStyle(palette.text)
                    SetupStatusRow(title: "Email authentication", detail: "Needs SUPABASE_URL and anon key", ready: false)
                    FormaDivider()
                    SetupStatusRow(title: "Cloud sync and RLS", detail: "Schema and policies are in supabase/migrations", ready: false)
                    FormaDivider()
                    SetupStatusRow(title: "Live AI coach", detail: "Runs through the coach-chat and coach-plan Edge Functions with OpenAI on the server", ready: false)
                    FormaDivider()
                    SetupStatusRow(title: "On-device plan engine", detail: "Works without a backend", ready: true)
                    FormaDivider()
                    SetupStatusRow(title: "Workout tracker and local reminders", detail: "Built on native iOS APIs", ready: true)
                }

                FormaCard(style: .raised) {
                    Text("How to connect")
                        .font(FormaFont.displayFont(17, weight: .semibold))
                        .foregroundStyle(palette.text)
                    SetupStep(number: 1, text: "Create a Supabase project and apply the migrations in supabase/migrations.")
                    SetupStep(number: 2, text: "Deploy the three Edge Functions and set OPENAI_API_KEY as a server secret.")
                    SetupStep(number: 3, text: "In Xcode, set SUPABASE_URL and SUPABASE_ANON_KEY build settings, then build again.")
                    Text("The full guide is in native/SETUP.md. Never add a service-role key or an OpenAI key to the app target.")
                        .font(FormaFont.bodyFont(12))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.config.allowsPreviewData {
                    FormaCard(style: .accent) {
                        Text("Debug preview")
                            .font(FormaFont.displayFont(16, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text("Explore the full interface with data stored only on this device. No account, no sync, no live AI — the coach answers from on-device logic and is labelled as preview.")
                            .font(FormaFont.bodyFont(13))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        SecondaryButton(title: "Explore preview data", systemImage: "exclamationmark.circle") {
                            showPreviewConfirm = true
                        }
                    }
                }

                Text("Forma offers general fitness guidance, not medical advice. If you feel sharp pain, dizziness, chest discomfort, or shortness of breath, stop and seek help from a qualified professional.")
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xxxl)
            .padding(.bottom, Spacing.huge)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(FormaBackground())
        .alert("Use preview data?", isPresented: $showPreviewConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Explore") {
                Task { await model.startPreview() }
            }
        } message: {
            Text("This is a debug-only mode. Data stays on this iPhone and is not synced. You can leave it from Profile.")
        }
    }
}

private struct SetupStatusRow: View {
    var title: String
    var detail: String
    var ready: Bool
    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: ready ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                .font(.system(size: 15))
                .foregroundStyle(ready ? palette.accentText : palette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FormaFont.bodyFont(13, weight: .medium))
                    .foregroundStyle(palette.text)
                Text(detail)
                    .font(FormaFont.bodyFont(12))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SetupStep: View {
    var number: Int
    var text: String
    @Environment(\.formaPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text("\(number)")
                .font(FormaFont.bodyFont(11, weight: .semibold))
                .foregroundStyle(palette.accentInk)
                .frame(width: 20, height: 20)
                .background(palette.accent, in: Circle())
            Text(text)
                .font(FormaFont.bodyFont(13))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
