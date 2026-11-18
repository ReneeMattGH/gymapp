import SwiftUI

struct CommunityConnectionsSection: View {
    var store: CommunityStore
    @Environment(\.formaPalette) private var palette

    private var accepted: [CommunityConnection] {
        store.connections.filter { $0.isAccepted }
    }

    private var pendingSent: [CommunityConnection] {
        store.connections.filter { $0.isPending && !$0.isIncoming }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            if let error = store.connectionsError {
                ErrorBanner(message: error) {
                    Task { await store.loadConnections() }
                }
            }

            if store.connectionsLoading && store.connections.isEmpty {
                LoadingCard(label: "Loading connections")
            } else {
                if !store.incomingRequests.isEmpty {
                    FormaCard {
                        SectionHeader(title: "Requests for you")
                        ForEach(store.incomingRequests) { request in
                            HStack(spacing: Spacing.md) {
                                NavigationLink(value: CommunityRoute.member(request.userID)) {
                                    CommunityMemberRow(
                                        member: CommunityMember.requestRow(
                                            id: request.userID,
                                            username: request.username,
                                            displayName: request.displayName,
                                            avatarURL: request.avatarURL
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                                requestButtons(request)
                            }
                            if request.connectionID != store.incomingRequests.last?.connectionID {
                                FormaDivider()
                            }
                        }
                    }
                }

                FormaCard {
                    SectionHeader(title: "Connections")
                    if accepted.isEmpty {
                        Text("No connections yet. Accepted requests appear here, and messaging only opens after a connection is accepted.")
                            .font(FormaFont.bodyFont(13))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(accepted) { connection in
                            NavigationLink(value: CommunityRoute.member(connection.userID)) {
                                CommunityMemberRow(member: connection.asMember)
                            }
                            .buttonStyle(.plain)
                            if connection.connectionID != accepted.last?.connectionID {
                                FormaDivider()
                            }
                        }
                    }
                }

                if !pendingSent.isEmpty {
                    FormaCard {
                        SectionHeader(title: "Sent requests")
                        ForEach(pendingSent) { connection in
                            NavigationLink(value: CommunityRoute.member(connection.userID)) {
                                HStack(spacing: Spacing.md) {
                                    CommunityMemberRow(member: connection.asMember)
                                }
                            }
                            .buttonStyle(.plain)
                            if connection.connectionID != pendingSent.last?.connectionID {
                                FormaDivider()
                            }
                        }
                        Text("Requests expire from this list only after the other member responds. You can send one request per member at a time.")
                            .font(FormaFont.bodyFont(11))
                            .foregroundStyle(palette.textTertiary)
                    }
                }

                if store.incomingRequests.isEmpty && accepted.isEmpty && pendingSent.isEmpty && !store.connectionsLoading {
                    FormaEmptyState(
                        systemImage: "person.2",
                        title: "No connections yet",
                        message: "Find members at your gym or nearby, then send a connection request. Nothing here is generated for you.",
                        actionTitle: "Find members",
                        action: nil
                    )
                }

                NavigationLink(value: CommunityRoute.blockedMembers) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "hand.raised")
                            .foregroundStyle(palette.textSecondary)
                        Text("Blocked members")
                            .font(FormaFont.bodyFont(14, weight: .medium))
                            .foregroundStyle(palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(Spacing.lg)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .task { await store.loadConnections() }
    }

    private func requestButtons(_ request: IncomingConnectionRequest) -> some View {
        HStack(spacing: Spacing.sm) {
            Button {
                Task { await store.respond(to: request, accept: true) }
            } label: {
                Group {
                    if store.isBusy("respond-\(request.connectionID)") {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("Accept")
                            .font(FormaFont.bodyFont(12, weight: .semibold))
                    }
                }
                .foregroundStyle(palette.accentInk)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(palette.accent, in: Capsule())
            }
            .buttonStyle(PressableScaleStyle())

            Button {
                Task { await store.respond(to: request, accept: false) }
            } label: {
                Text("Decline")
                    .font(FormaFont.bodyFont(12, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 6)
                    .background(palette.surfaceRaised, in: Capsule())
            }
            .buttonStyle(PressableScaleStyle())
        }
    }
}

struct CommunityConnectionRequestsView: View {
    var store: CommunityStore
    @Environment(\.formaPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if store.incomingRequests.isEmpty {
                    FormaEmptyState(
                        systemImage: "tray",
                        title: "No pending requests",
                        message: "Requests appear here only when a real member sends one."
                    )
                } else {
                    ForEach(store.incomingRequests) { request in
                        FormaCard {
                            HStack(spacing: Spacing.md) {
                                NavigationLink(value: CommunityRoute.member(request.userID)) {
                                    CommunityMemberRow(
                                        member: CommunityMember.requestRow(
                                            id: request.userID,
                                            username: request.username,
                                            displayName: request.displayName,
                                            avatarURL: request.avatarURL
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            Text("Sent \(CommunityTime.short(request.createdAt))")
                                .font(FormaFont.bodyFont(11))
                                .foregroundStyle(palette.textTertiary)
                            HStack(spacing: Spacing.md) {
                                PrimaryButton(title: "Accept", systemImage: "checkmark") {
                                    Task { await store.respond(to: request, accept: true) }
                                }
                                SecondaryButton(title: "Decline", destructive: true) {
                                    Task { await store.respond(to: request, accept: false) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .background(FormaBackground())
        .navigationTitle("Requests")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadBootstrap() }
    }
}

struct CommunityBlockedMembersView: View {
    var store: CommunityStore
    @Environment(\.formaPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Blocking hides discovery, posts and messages in both directions. Unblocking restores normal rules; it does not restore a removed connection.")
                    .font(FormaFont.bodyFont(12))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if store.blockedLoading {
                    LoadingCard(label: "Loading blocked members")
                } else if store.blockedMembers.isEmpty {
                    FormaEmptyState(
                        systemImage: "hand.raised",
                        title: "No blocked members",
                        message: "Members you block appear here."
                    )
                } else {
                    ForEach(store.blockedMembers) { member in
                        FormaCard {
                            HStack(spacing: Spacing.md) {
                                CommunityAvatar(
                                    name: member.displayName ?? member.username ?? "Member",
                                    urlString: member.avatarURL,
                                    size: 38
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.displayName ?? member.username ?? "Member")
                                        .font(FormaFont.bodyFont(14, weight: .semibold))
                                        .foregroundStyle(palette.text)
                                    if let username = member.username {
                                        Text("@\(username)")
                                            .font(FormaFont.bodyFont(12))
                                            .foregroundStyle(palette.textSecondary)
                                    }
                                    if let blockedAt = member.blockedAt {
                                        Text("Blocked \(CommunityTime.short(blockedAt))")
                                            .font(FormaFont.bodyFont(11))
                                            .foregroundStyle(palette.textTertiary)
                                    }
                                }
                                Spacer()
                                SecondaryButton(title: "Unblock") {
                                    Task { await store.block(userID: member.userID, blocked: false) }
                                }
                                .frame(width: 110)
                            }
                        }
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .background(FormaBackground())
        .navigationTitle("Blocked")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadBlockedMembers() }
    }
}

extension CommunityConnection {
    var asMember: CommunityMember {
        CommunityMember(
            userID: userID,
            username: username,
            displayName: displayName,
            avatarURL: avatarURL,
            bio: nil,
            interests: [],
            workoutCategories: [],
            gymName: nil,
            area: nil,
            city: nil,
            connectionStatus: isAccepted ? .accepted : .pendingSent
        )
    }
}

extension CommunityMember {
    static func requestRow(id: String, username: String, displayName: String, avatarURL: String?) -> CommunityMember {
        CommunityMember(
            userID: id,
            username: username,
            displayName: displayName,
            avatarURL: avatarURL,
            bio: nil,
            interests: [],
            workoutCategories: [],
            gymName: nil,
            area: nil,
            city: nil,
            connectionStatus: .pendingReceived
        )
    }
}
