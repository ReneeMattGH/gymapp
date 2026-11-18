import SwiftUI

private let communityInterests = [
    "Strength", "Cardio", "Yoga", "HIIT", "Mobility",
    "Bodybuilding", "Running", "CrossFit", "Calisthenics", "Powerlifting",
]

struct CommunityDiscoverSection: View {
    var store: CommunityStore
    @Binding var showReportFor: CommunityReportPayload?

    @Environment(\.formaPalette) private var palette
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            FormaTextField(
                placeholder: "Search members, gyms or areas",
                text: $query,
                capitalization: .never
            )
            .onChange(of: query) { _, newValue in
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await store.searchDiscover(query: newValue)
                }
            }

            CommunitySectionChips(
                items: CommunityScope.allCases,
                title: \.title,
                selection: store.discoverScope
            ) { scope in
                Task { await store.setDiscoverScope(scope) }
            }
            .padding(.horizontal, -Spacing.xl)

            Text(store.discoverScope.detail)
                .font(FormaFont.bodyFont(12))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    FormaChip(label: "Any focus", selected: store.discoverInterest.isEmpty) {
                        Task { await store.setDiscoverInterest("") }
                    }
                    ForEach(communityInterests, id: \.self) { interest in
                        FormaChip(label: interest, selected: store.discoverInterest == interest) {
                            Task {
                                await store.setDiscoverInterest(store.discoverInterest == interest ? "" : interest)
                            }
                        }
                    }
                }
            }
            .scrollClipDisabled()

            if let error = store.discoverError {
                ErrorBanner(message: error) {
                    Task { await store.loadDiscover(reset: true) }
                }
            }

            if store.discoverLoading {
                LoadingCard(label: "Looking for members")
            } else if store.discoverResults.isEmpty {
                FormaEmptyState(
                    systemImage: "person.2",
                    title: "No members to show",
                    message: emptyMessage,
                    actionTitle: store.discoverScope == .gym ? "Change gym or area" : nil,
                    action: store.discoverScope == .gym ? { store.discoverScope = .area; Task { await store.loadDiscover(reset: true) } } : nil
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(store.discoverResults) { member in
                        NavigationLink(value: CommunityRoute.member(member.userID)) {
                            CommunityMemberRow(member: member, trailing: AnyView(action(for: member)))
                                .padding(.vertical, Spacing.md)
                        }
                        .buttonStyle(.plain)
                        FormaDivider()
                    }
                }

                if store.discoverHasMore {
                    SecondaryButton(title: "Load more members", systemImage: "arrow.down.circle") {
                        Task { await store.loadDiscover(reset: false) }
                    }
                    .onAppear {
                        Task { await store.loadDiscover(reset: false) }
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .task {
            if store.discoverResults.isEmpty {
                await store.loadDiscover(reset: true)
            }
        }
    }

    private var emptyMessage: String {
        switch store.discoverScope {
        case .gym:
            return "No one who shares your gym has opted into discovery yet. Members only appear here after they join a gym, create a community profile and turn discovery on."
        case .area:
            return "No one in your area group has opted into nearby discovery yet. Choosing an area never reveals anyone's live location."
        case .all:
            return "No discoverable members match this search yet."
        }
    }

    @ViewBuilder
    private func action(for member: CommunityMember) -> some View {
        if store.isBusy("connect-\(member.userID)") {
            ProgressView().controlSize(.small)
        } else {
            switch member.connectionStatus {
            case .none:
                Button {
                    Task { await store.sendConnectionRequest(to: member) }
                } label: {
                    Text("Connect")
                        .font(FormaFont.bodyFont(12, weight: .semibold))
                        .foregroundStyle(palette.accentInk)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 6)
                        .background(palette.accent, in: Capsule())
                }
                .buttonStyle(PressableScaleStyle())
            default:
                CommunityConnectionBadge(status: member.connectionStatus)
            }
        }
    }
}

// MARK: - Member profile

struct CommunityMemberProfileView: View {
    var store: CommunityStore
    var userID: String

    @Environment(\.formaPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var profile: CommunityPublicProfile?
    @State private var loading = true
    @State private var loadError: String?
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var confirmRemove = false
    @State private var conversation: CommunityConversation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if loading {
                    LoadingCard(label: "Loading profile")
                } else if let loadError {
                    ErrorBanner(message: loadError) {
                        Task { await load() }
                    }
                } else if let profile {
                    header(profile)
                    details(profile)
                    actions(profile)
                } else {
                    FormaEmptyState(
                        systemImage: "person.crop.circle.badge.questionmark",
                        title: "Profile not available",
                        message: "This member is private, in a different age group, blocked, or no longer discoverable. The server decides what can be shown."
                    )
                }
            }
            .padding(Spacing.xl)
        }
        .background(FormaBackground())
        .navigationTitle("Member")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showReport) {
            if let profile {
                CommunityReportSheet(
                    targetType: .profile,
                    targetID: profile.userID,
                    targetLabel: "@\(profile.username)"
                ) { reason, details in
                    await store.report(targetType: .profile, targetID: profile.userID, reason: reason, details: details)
                }
            }
        }
        .confirmationDialog("Block @\(profile?.username ?? "member")?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block member", role: .destructive) {
                Task {
                    await store.block(userID: userID, blocked: true)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Blocking removes the connection, hides their posts, and stops messages and discovery in both directions.")
        }
        .confirmationDialog("Remove this connection?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove connection", role: .destructive) {
                Task {
                    if let connection = store.connections.first(where: { $0.userID == userID }) {
                        await store.removeConnection(connection)
                    }
                    await load()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func load() async {
        loading = true
        loadError = nil
        profile = await store.loadPublicProfile(userID: userID)
        loading = false
        if let existing = store.conversations.first(where: { $0.userID == userID }) {
            conversation = existing
        } else {
            await store.loadConversations()
            conversation = store.conversations.first(where: { $0.userID == userID })
        }
    }

    private func header(_ profile: CommunityPublicProfile) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            CommunityAvatar(name: profile.displayName, urlString: profile.avatarURL, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(FormaFont.displayFont(22, weight: .bold))
                    .foregroundStyle(palette.text)
                Text("@\(profile.username)")
                    .font(FormaFont.bodyFont(13))
                    .foregroundStyle(palette.textSecondary)
                if let joined = profile.joinedAt {
                    Text("Member since \(Formatters.longDate(joined))")
                        .font(FormaFont.bodyFont(11))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
            CommunityConnectionBadge(status: profile.connectionStatus)
        }
    }

    private func details(_ profile: CommunityPublicProfile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let bio = profile.bio, !bio.isEmpty {
                FormaCard {
                    Text(bio)
                        .font(FormaFont.bodyFont(14))
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            FormaCard {
                KeyValueRow(label: "Gym", value: profile.gymName ?? "Not shared")
                FormaDivider()
                KeyValueRow(
                    label: "Area",
                    value: [profile.area, profile.city].compactMap { $0 }.joined(separator: ", ").isEmpty
                        ? "Not shared"
                        : [profile.area, profile.city].compactMap { $0 }.joined(separator: ", ")
                )
                FormaDivider()
                KeyValueRow(label: "Shared context", value: sharedContext(profile))
            }

            if !profile.interests.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader(title: "Interests")
                    FlowLayout(spacing: Spacing.sm) {
                        ForEach(profile.interests, id: \.self) { interest in
                            TagLabel(text: interest)
                        }
                    }
                }
            }

            if !profile.workoutCategories.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader(title: "Training focus")
                    FlowLayout(spacing: Spacing.sm) {
                        ForEach(profile.workoutCategories, id: \.self) { category in
                            TagLabel(text: category, color: palette.textSecondary)
                        }
                    }
                }
            }

            NoticeBanner(
                message: "Forma never shows a member's exact location, live presence at a gym, email or phone number.",
                systemImage: "location.slash"
            )
        }
    }

    private func sharedContext(_ profile: CommunityPublicProfile) -> String {
        switch (profile.sharedGym, profile.sharedArea) {
        case (true, true): return "Same gym and nearby area"
        case (true, false): return "Same gym"
        case (false, true): return "Nearby area"
        case (false, false): return "Connected through the community"
        }
    }

    @ViewBuilder
    private func actions(_ profile: CommunityPublicProfile) -> some View {
        VStack(spacing: Spacing.md) {
            switch profile.connectionStatus {
            case .none:
                PrimaryButton(title: "Send connection request", systemImage: "person.badge.plus") {
                    Task {
                        await store.sendConnectionRequest(toUserID: profile.userID)
                        await load()
                    }
                }
            case .pendingSent:
                NoticeBanner(message: "Your request is waiting for \(profile.displayName) to respond.", systemImage: "clock")
            case .pendingReceived:
                if let request = store.incomingRequests.first(where: { $0.userID == profile.userID }) {
                    PrimaryButton(title: "Accept request", systemImage: "checkmark") {
                        Task {
                            await store.respond(to: request, accept: true)
                            await load()
                        }
                    }
                    SecondaryButton(title: "Decline", destructive: true) {
                        Task {
                            await store.respond(to: request, accept: false)
                            await load()
                        }
                    }
                }
            case .accepted:
                if let conversation {
                    NavigationLink(value: CommunityRoute.conversation(conversation)) {
                        Text("Message \(profile.displayName)")
                            .font(FormaFont.bodyFont(14, weight: .semibold))
                            .foregroundStyle(palette.accentInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(palette.accent, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                }
                SecondaryButton(title: "Remove connection", destructive: true) {
                    confirmRemove = true
                }
            case .blocked:
                SecondaryButton(title: "Unblock member") {
                    Task {
                        await store.block(userID: userID, blocked: false)
                        await load()
                    }
                }
            }

            HStack(spacing: Spacing.md) {
                SecondaryButton(title: "Report", systemImage: "flag") {
                    showReport = true
                }
                if profile.connectionStatus != .blocked {
                    SecondaryButton(title: "Block", systemImage: "hand.raised", destructive: true) {
                        confirmBlock = true
                    }
                }
            }
        }
    }
}
