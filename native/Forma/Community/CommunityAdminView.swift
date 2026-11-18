import SwiftUI

private enum AdminSection: String, CaseIterable, Identifiable {
    case reports
    case gyms
    case audit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reports: "Reports"
        case .gyms: "Gyms"
        case .audit: "Audit log"
        }
    }
}

struct CommunityAdminView: View {
    var store: CommunityStore

    @Environment(\.formaPalette) private var palette
    @State private var section: AdminSection = .reports

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                NoticeBanner(
                    message: "Every moderation action is checked against the administrator role on the server. This screen only shows controls; it cannot grant access.",
                    systemImage: "lock.shield"
                )

                if let error = store.adminError {
                    ErrorBanner(message: error) {
                        Task { await store.loadAdminData() }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(AdminSection.allCases) { option in
                            FormaChip(label: option.title, selected: section == option) {
                                section = option
                            }
                        }
                    }
                }
                .scrollClipDisabled()

                if store.adminLoading && store.adminReports.isEmpty && store.adminGyms.isEmpty {
                    LoadingCard(label: "Loading moderation data")
                } else {
                    switch section {
                    case .reports:
                        reportsSection
                    case .gyms:
                        gymsSection
                    case .audit:
                        auditSection
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .background(FormaBackground())
        .navigationTitle("Moderation")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.loadAdminData() }
        .task {
            if store.adminReports.isEmpty && store.adminGyms.isEmpty && store.adminAudit.isEmpty {
                await store.loadAdminData()
            }
        }
    }

    @ViewBuilder
    private var reportsSection: some View {
        CommunityAdminSuspensionCard(store: store)

        if store.adminReports.isEmpty {
            FormaEmptyState(
                systemImage: "checkmark.shield",
                title: "No reports",
                message: "Member reports appear here. Nothing is generated."
            )
        } else {
            ForEach(store.adminReports) { report in
                CommunityAdminReportCard(store: store, report: report)
            }
        }
    }

    @ViewBuilder
    private var gymsSection: some View {
        if store.adminGyms.isEmpty {
            FormaEmptyState(
                systemImage: "building.2",
                title: "No gyms",
                message: "Gym submissions appear here for review."
            )
        } else {
            ForEach(store.adminGyms) { gym in
                CommunityAdminGymCard(store: store, gym: gym)
            }
        }
    }

    @ViewBuilder
    private var auditSection: some View {
        if store.adminAudit.isEmpty {
            FormaEmptyState(
                systemImage: "list.bullet.rectangle",
                title: "No actions yet",
                message: "Every moderation action is recorded here by the server."
            )
        } else {
            FormaCard {
                ForEach(store.adminAudit) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(humanized(entry.action))
                            .font(FormaFont.bodyFont(13, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text("\(entry.targetType) · \(entry.targetID ?? "—")")
                            .font(FormaFont.bodyFont(10))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                        if let note = entry.note, !note.isEmpty {
                            Text(note)
                                .font(FormaFont.bodyFont(12))
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(CommunityTime.short(entry.createdAt))
                            .font(FormaFont.bodyFont(10))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.vertical, Spacing.sm)
                    if entry.id != store.adminAudit.last?.id {
                        FormaDivider()
                    }
                }
            }
        }
    }

    private func humanized(_ action: String) -> String {
        action.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Report card

private struct CommunityAdminReportCard: View {
    var store: CommunityStore
    var report: CommunityModerationReport

    @Environment(\.formaPalette) private var palette
    @State private var note = ""
    @State private var confirmRemove = false
    @State private var confirmSuspend = false

    private var isOpen: Bool { report.status == "open" }
    private var canRemoveContent: Bool { report.targetType == "post" || report.targetType == "comment" }

    var body: some View {
        FormaCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.reason.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(FormaFont.bodyFont(14, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text("@\(report.reporterUsername ?? "unknown") reported a \(report.targetType)")
                        .font(FormaFont.bodyFont(11))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                TagLabel(
                    text: report.status,
                    color: isOpen ? palette.warning : palette.textSecondary
                )
            }

            if let details = report.details, !details.isEmpty {
                Text(details)
                    .font(FormaFont.bodyFont(13))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Target \(report.targetID)")
                .font(FormaFont.bodyFont(10))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)

            Text("Reported \(CommunityTime.short(report.createdAt))")
                .font(FormaFont.bodyFont(10))
                .foregroundStyle(palette.textTertiary)

            if isOpen {
                FormaTextField(placeholder: "Review note (optional)", text: $note)

                HStack(spacing: Spacing.sm) {
                    Button("Dismiss") {
                        Task { await store.resolveReport(report, action: "dismiss", note: trimmedNote) }
                    }
                    .font(FormaFont.bodyFont(12, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 7)
                    .background(palette.surfaceRaised, in: Capsule())

                    if canRemoveContent {
                        Button("Remove content") {
                            confirmRemove = true
                        }
                        .font(FormaFont.bodyFont(12, weight: .semibold))
                        .foregroundStyle(palette.danger)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 7)
                        .background(palette.dangerSoft, in: Capsule())
                    }

                    Button("Suspend author") {
                        confirmSuspend = true
                    }
                    .font(FormaFont.bodyFont(12, weight: .semibold))
                    .foregroundStyle(palette.danger)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 7)
                    .background(palette.dangerSoft, in: Capsule())
                }
            }
        }
        .confirmationDialog("Remove the reported content?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove content", role: .destructive) {
                Task { await store.resolveReport(report, action: "remove_content", note: trimmedNote) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The content is hidden from the community. The action is recorded in the audit log.")
        }
        .confirmationDialog("Suspend the reported account?", isPresented: $confirmSuspend, titleVisibility: .visible) {
            Button("Suspend account", role: .destructive) {
                Task { await store.resolveReport(report, action: "suspend_user", note: trimmedNote) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Suspension blocks posting, connecting and messaging in Community. The member can still read their existing data.")
        }
    }

    private var trimmedNote: String? {
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Gym card

private struct CommunityAdminGymCard: View {
    var store: CommunityStore
    var gym: CommunityAdminGym

    @Environment(\.formaPalette) private var palette
    @State private var note = ""
    @State private var confirmReject = false

    var body: some View {
        FormaCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(gym.name)
                        .font(FormaFont.bodyFont(14, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text([gym.area, gym.city].compactMap { $0 }.joined(separator: ", "))
                        .font(FormaFont.bodyFont(12))
                        .foregroundStyle(palette.textSecondary)
                    if let address = gym.address, !address.isEmpty {
                        Text(address)
                            .font(FormaFont.bodyFont(11))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
                TagLabel(
                    text: gym.verificationStatus,
                    color: gym.verificationStatus == "verified" ? palette.success : palette.warning
                )
            }

            Text("Submitted \(CommunityTime.short(gym.createdAt))")
                .font(FormaFont.bodyFont(10))
                .foregroundStyle(palette.textTertiary)

            if gym.verificationStatus == "pending" {
                FormaTextField(placeholder: "Review note (optional)", text: $note)
                HStack(spacing: Spacing.sm) {
                    Button {
                        Task { await store.reviewGym(gym, approve: true, note: trimmedNote) }
                    } label: {
                        Text("Approve")
                            .font(FormaFont.bodyFont(12, weight: .semibold))
                            .foregroundStyle(palette.accentInk)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, 7)
                            .background(palette.accent, in: Capsule())
                    }
                    .buttonStyle(PressableScaleStyle())

                    Button {
                        confirmReject = true
                    } label: {
                        Text("Reject")
                            .font(FormaFont.bodyFont(12, weight: .semibold))
                            .foregroundStyle(palette.danger)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, 7)
                            .background(palette.dangerSoft, in: Capsule())
                    }
                    .buttonStyle(PressableScaleStyle())
                }
            }
        }
        .confirmationDialog("Reject this gym submission?", isPresented: $confirmReject, titleVisibility: .visible) {
            Button("Reject gym", role: .destructive) {
                Task { await store.reviewGym(gym, approve: false, note: trimmedNote) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rejected gyms stay out of member search. The action is recorded in the audit log.")
        }
    }

    private var trimmedNote: String? {
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Suspension

private struct CommunityAdminSuspensionCard: View {
    var store: CommunityStore

    @Environment(\.formaPalette) private var palette
    @State private var userID = ""
    @State private var reason = ""
    @State private var confirmSuspend = false

    private var trimmedID: String { userID.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        FormaCard {
            SectionHeader(title: "Account status")
            Text("Paste a member's user ID to suspend or reinstate their Community access. The server rejects this call for non-admins.")
                .font(FormaFont.bodyFont(11))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            FormaTextField(placeholder: "Member user ID", text: $userID, capitalization: .never)
            FormaTextField(placeholder: "Reason (optional)", text: $reason)

            HStack(spacing: Spacing.sm) {
                Button("Suspend") {
                    confirmSuspend = true
                }
                .font(FormaFont.bodyFont(12, weight: .semibold))
                .foregroundStyle(palette.danger)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 7)
                .background(palette.dangerSoft, in: Capsule())
                .disabled(trimmedID.isEmpty)
                .opacity(trimmedID.isEmpty ? 0.45 : 1)

                Button("Reinstate") {
                    Task {
                        await store.setSuspension(userID: trimmedID, suspended: false, reason: trimmedReason)
                    }
                }
                .font(FormaFont.bodyFont(12, weight: .semibold))
                .foregroundStyle(palette.text)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 7)
                .background(palette.surfaceRaised, in: Capsule())
                .disabled(trimmedID.isEmpty)
                .opacity(trimmedID.isEmpty ? 0.45 : 1)
            }
        }
        .confirmationDialog("Suspend this account?", isPresented: $confirmSuspend, titleVisibility: .visible) {
            Button("Suspend account", role: .destructive) {
                Task {
                    await store.setSuspension(userID: trimmedID, suspended: true, reason: trimmedReason)
                    userID = ""
                    reason = ""
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Suspension blocks posting, connecting and messaging. The action is recorded in the audit log.")
        }
    }

    private var trimmedReason: String? {
        let value = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
