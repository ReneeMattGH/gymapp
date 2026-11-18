import SwiftUI

enum CommunitySection: String, CaseIterable, Identifiable {
    case home
    case discover
    case connections
    case messages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .discover: "Discover"
        case .connections: "Connections"
        case .messages: "Messages"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .discover: "safari"
        case .connections: "person.2"
        case .messages: "bubble.left.and.bubble.right"
        }
    }
}

enum CommunityRoute: Hashable {
    case member(String)
    case notifications
    case settings
    case profileEditor
    case gymSelection
    case connectionRequests
    case blockedMembers
    case admin
    case feed
    case conversation(CommunityConversation)
}

struct CommunityRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette
    @State private var store = CommunityStore()
    @State private var section: CommunitySection = .home
    @State private var path = NavigationPath()
    @State private var showReportFor: CommunityReportPayload?

    private var isAvailable: Bool {
        model.communityService != nil && model.user != nil && !model.isPreview
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isAvailable {
                    content
                } else {
                    CommunityUnavailableView(isPreview: model.isPreview, isSignedOut: model.user == nil)
                }
            }
            .background(FormaBackground())
            .navigationDestination(for: CommunityRoute.self) { route in
                destination(for: route)
            }
        }
        .task(id: model.user?.id) {
            await store.configure(service: model.communityService, userID: model.user?.id)
            applyDeepLink(model.pendingDeepLink)
        }
        .onChange(of: model.pendingDeepLink, initial: true) { _, link in
            applyDeepLink(link)
        }
        .sheet(item: $showReportFor) { payload in
            CommunityReportSheet(
                targetType: payload.targetType,
                targetID: payload.targetID,
                targetLabel: payload.label
            ) { reason, details in
                await store.report(targetType: payload.targetType, targetID: payload.targetID, reason: reason, details: details)
            }
        }
    }

    private func applyDeepLink(_ link: AppDeepLink?) {
        guard isAvailable, let link else { return }
        switch link {
        case .community:
            path = NavigationPath()
            section = .home
            model.consumeDeepLink(.community)
        case .connectionRequests:
            path = NavigationPath()
            section = .connections
            path.append(CommunityRoute.connectionRequests)
            model.consumeDeepLink(.connectionRequests)
        case .messages:
            path = NavigationPath()
            section = .messages
            model.consumeDeepLink(.messages)
        default:
            break
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                CommunitySectionChips(
                    items: CommunitySection.allCases,
                    title: \.title,
                    selection: section
                ) { newSection in
                    guard newSection != section else { return }
                    section = newSection
                    Task {
                        switch newSection {
                        case .discover:
                            await store.loadDiscover(reset: true)
                        case .connections:
                            await store.loadConnections()
                        case .messages:
                            await store.loadConversations()
                        case .home:
                            await store.loadBootstrap()
                        }
                    }
                }

                if let error = store.actionError {
                    ErrorBanner(message: error) {
                        store.clearActionError()
                    }
                }

                if store.isSuspended {
                    NoticeBanner(
                        message: "Community access for this account is paused. You can still read your existing data, but posting, connecting and messaging are blocked by the server.",
                        systemImage: "hand.raised.fill"
                    )
                }

                switch store.phase {
                case .unavailable:
                    CommunityUnavailableView(isPreview: false, isSignedOut: false)
                case .loading:
                    LoadingCard(label: "Loading your community")
                case .failed(let message):
                    ErrorBanner(message: message) {
                        Task { await store.loadBootstrap() }
                    }
                case .ready:
                    switch section {
                    case .home:
                        CommunityHomeSection(store: store, showReportFor: $showReportFor) { target in
                            section = target
                            if target == .discover {
                                Task { await store.loadDiscover(reset: true) }
                            }
                        }
                    case .discover:
                        CommunityDiscoverSection(store: store, showReportFor: $showReportFor)
                    case .connections:
                        CommunityConnectionsSection(store: store)
                    case .messages:
                        CommunityMessagesSection(store: store)
                    }
                }
            }
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.huge)
        }
        .refreshable {
            await store.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            PageHeading(
                eyebrow: "Community",
                title: "Train together.",
                subtitle: "Find real members who chose the same gym or a nearby area. Discovery uses your saved gym and area, not your live location."
            )
            Spacer(minLength: Spacing.sm)
            HStack(spacing: Spacing.sm) {
                NavigationLink(value: CommunityRoute.notifications) {
                    badgeIcon(systemImage: "bell", count: store.unreadNotifications)
                }
                NavigationLink(value: CommunityRoute.settings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .frame(width: 38, height: 38)
                        .background(palette.surface, in: Circle())
                        .overlay { Circle().strokeBorder(palette.border, lineWidth: 1) }
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, Spacing.xl)
    }

    private func badgeIcon(systemImage: String, count: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.text)
                .frame(width: 38, height: 38)
                .background(palette.surface, in: Circle())
                .overlay { Circle().strokeBorder(palette.border, lineWidth: 1) }
            if count > 0 {
                Text(count > 9 ? "9+" : "\(count)")
                    .font(FormaFont.bodyFont(9, weight: .bold))
                    .foregroundStyle(palette.accentInk)
                    .frame(minWidth: 16, minHeight: 16)
                    .padding(.horizontal, 2)
                    .background(palette.accent, in: Capsule())
                    .offset(x: 4, y: -3)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: CommunityRoute) -> some View {
        switch route {
        case .member(let userID):
            CommunityMemberProfileView(store: store, userID: userID)
        case .notifications:
            CommunityNotificationsView(store: store)
        case .settings:
            CommunitySettingsView(store: store)
        case .profileEditor:
            CommunityProfileEditorView(store: store)
        case .gymSelection:
            CommunityGymSelectionView(store: store)
        case .connectionRequests:
            CommunityConnectionRequestsView(store: store)
        case .blockedMembers:
            CommunityBlockedMembersView(store: store)
        case .admin:
            CommunityAdminView(store: store)
        case .feed:
            CommunityFeedScreen(store: store, showReportFor: $showReportFor)
        case .conversation(let conversation):
            CommunityMessageThreadView(store: store, conversation: conversation)
        }
    }
}

// MARK: - Unavailable

struct CommunityUnavailableView: View {
    var isPreview: Bool
    var isSignedOut: Bool

    @Environment(\.formaPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                PageHeading(
                    eyebrow: "Community",
                    title: "Real members only.",
                    subtitle: "Community shows people who actually created an account, chose a gym or area, and opted into discovery."
                )
                FormaCard(style: .raised) {
                    Image(systemName: isPreview ? "person.crop.circle.badge.exclamationmark" : "person.2.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(palette.accentText)
                    Text(headline)
                        .font(FormaFont.displayFont(18, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(detail)
                        .font(FormaFont.bodyFont(13))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FormaCard {
                    Text("What Community does not do")
                        .font(FormaFont.displayFont(16, weight: .semibold))
                        .foregroundStyle(palette.text)
                    bullet("It never shows live location or confirms you are at a gym.")
                    bullet("It does not create sample members, posts or messages to fill space.")
                    bullet("It does not need location permission. Matching uses only the gym or area you pick.")
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xxxl)
            .padding(.bottom, Spacing.huge)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var headline: String {
        if isPreview {
            return "Community is off in preview mode"
        }
        if isSignedOut {
            return "Sign in to join your gym community"
        }
        return "Community needs the live backend"
    }

    private var detail: String {
        if isPreview {
            return "Preview data stays on this device, so there are no real members to discover. Connect a Supabase project and use a real account to use Community."
        }
        if isSignedOut {
            return "Your account is real, but you are not signed in. Sign in to choose a gym or area and see members who opted into discovery."
        }
        return "This build has no Supabase credentials, so Community cannot load real members. Follow native/SETUP.md, then rebuild."
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(palette.accentText)
                .padding(.top, 2)
            Text(text)
                .font(FormaFont.bodyFont(13))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Home

struct CommunityHomeSection: View {
    var store: CommunityStore
    @Binding var showReportFor: CommunityReportPayload?
    var openSection: (CommunitySection) -> Void

    @Environment(\.formaPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            if store.profile == nil {
                FormaCard(style: .accent) {
                    Text("Create your community profile")
                        .font(FormaFont.displayFont(17, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text("Pick a username and display name. Only discoverable members can see your profile, and you choose whether your gym and area are shown.")
                        .font(FormaFont.bodyFont(13))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink(value: CommunityRoute.profileEditor) {
                        Text("Set up profile")
                            .font(FormaFont.bodyFont(14, weight: .semibold))
                            .foregroundStyle(palette.accentInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(palette.accent, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                }
            }

            placeCard

            HStack(spacing: Spacing.md) {
                StatTile(
                    value: "\(store.bootstrap?.membersAtGym ?? 0)",
                    label: "At your gym",
                    detail: "Members who picked the same gym",
                    accent: true
                )
                StatTile(
                    value: "\(store.bootstrap?.nearbyMembers ?? 0)",
                    label: "Nearby",
                    detail: "Same or adjacent area group"
                )
            }

            if store.incomingRequestCount > 0 {
                FormaCard {
                    SectionHeader(title: "Connection requests")
                    ForEach(store.incomingRequests.prefix(3)) { request in
                        HStack(spacing: Spacing.md) {
                            CommunityAvatar(name: request.displayName, urlString: request.avatarURL, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(request.displayName)
                                    .font(FormaFont.bodyFont(14, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                Text("@\(request.username)")
                                    .font(FormaFont.bodyFont(12))
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            requestButton("Accept", accent: true, busy: store.isBusy("respond-\(request.connectionID)")) {
                                Task { await store.respond(to: request, accept: true) }
                            }
                            requestButton("Decline", accent: false, busy: false) {
                                Task { await store.respond(to: request, accept: false) }
                            }
                        }
                        if request.connectionID != store.incomingRequests.prefix(3).last?.connectionID {
                            FormaDivider()
                        }
                    }
                    NavigationLink(value: CommunityRoute.connectionRequests) {
                        Text("Review all requests")
                            .font(FormaFont.bodyFont(13, weight: .medium))
                            .foregroundStyle(palette.accentText)
                    }
                }
            }

            memberSection(
                title: "Suggested at your gym",
                members: store.bootstrap?.suggestions ?? [],
                emptyMessage: "No discoverable members share your gym yet. Members appear here only after they join a gym and opt into discovery.",
                actionTitle: "Open discovery"
            ) {
                openSection(.discover)
            }

            memberSection(
                title: "Nearby community",
                members: store.bootstrap?.nearby ?? [],
                emptyMessage: "No one in your area group has opted into nearby discovery yet.",
                actionTitle: "Open discovery"
            ) {
                openSection(.discover)
            }

            FormaCard {
                SectionHeader(title: "Recent activity")
                if store.feed.isEmpty {
                    Text("No posts yet. Posts come from real members — this screen stays empty until someone posts.")
                        .font(FormaFont.bodyFont(13))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(store.feed.prefix(2)) { post in
                        CommunityPostSummary(post: post)
                        if post.id != store.feed.prefix(2).last?.id {
                            FormaDivider()
                        }
                    }
                }
                NavigationLink(value: CommunityRoute.feed) {
                    Text("Open community feed")
                        .font(FormaFont.bodyFont(13, weight: .medium))
                        .foregroundStyle(palette.accentText)
                }
            }

            if store.isAdmin {
                NavigationLink(value: CommunityRoute.admin) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(palette.accentText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Moderation")
                                .font(FormaFont.bodyFont(14, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text("Reports, gym reviews and the audit log")
                                .font(FormaFont.bodyFont(12))
                                .foregroundStyle(palette.textSecondary)
                        }
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
    }

    private var placeCard: some View {
        FormaCard(style: .raised) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Overline(text: "Your selection")
                    if let membership = store.membership {
                        Text(membership.gymName)
                            .font(FormaFont.displayFont(19, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text([membership.area, membership.city].compactMap { $0 }.joined(separator: ", "))
                            .font(FormaFont.bodyFont(12))
                            .foregroundStyle(palette.textSecondary)
                        if membership.verificationStatus != "verified" {
                            TagLabel(text: "Awaiting review", color: palette.warning)
                        }
                    } else if let preferences = store.preferences, let area = preferences.area {
                        Text("\(area), \(preferences.city ?? "")")
                            .font(FormaFont.displayFont(19, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text("Area-only selection. No gym chosen.")
                            .font(FormaFont.bodyFont(12))
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        Text("No gym or area yet")
                            .font(FormaFont.displayFont(19, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text("Choose where you train to unlock discovery.")
                            .font(FormaFont.bodyFont(12))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                NavigationLink(value: CommunityRoute.gymSelection) {
                    Text(store.membership == nil ? "Choose" : "Change")
                        .font(FormaFont.bodyFont(12, weight: .semibold))
                        .foregroundStyle(palette.accentText)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 7)
                        .background(palette.accentSoft, in: Capsule())
                }
            }
            Text("Your gym or area selection is coarse. It never reveals your live location or confirms you are currently at that gym.")
                .font(FormaFont.bodyFont(11))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func memberSection(
        title: String,
        members: [CommunityMember],
        emptyMessage: String,
        actionTitle: String,
        onOpen: @escaping () -> Void
    ) -> some View {
        FormaCard {
            SectionHeader(title: title)
            if members.isEmpty {
                Text(emptyMessage)
                    .font(FormaFont.bodyFont(13))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(members) { member in
                    NavigationLink(value: CommunityRoute.member(member.userID)) {
                        CommunityMemberRow(member: member, trailing: AnyView(
                            store.isBusy("connect-\(member.userID)")
                                ? AnyView(ProgressView().controlSize(.small))
                                : AnyView(connectBadge(for: member))
                        ))
                    }
                    .buttonStyle(.plain)
                    if member.userID != members.last?.userID {
                        FormaDivider()
                    }
                }
            }
            Button(actionTitle, action: onOpen)
                .font(FormaFont.bodyFont(13, weight: .medium))
                .foregroundStyle(palette.accentText)
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func connectBadge(for member: CommunityMember) -> some View {
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

    private func requestButton(_ title: String, accent: Bool, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(title)
                        .font(FormaFont.bodyFont(12, weight: .semibold))
                }
            }
            .foregroundStyle(accent ? palette.accentInk : palette.text)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(accent ? palette.accent : palette.surfaceRaised, in: Capsule())
            .overlay { Capsule().strokeBorder(accent ? Color.clear : palette.border, lineWidth: 1) }
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(busy)
    }
}

struct CommunityPostSummary: View {
    var post: CommunityPost
    @Environment(\.formaPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Spacing.sm) {
                CommunityAvatar(name: post.displayName, urlString: post.avatarURL, size: 26)
                Text(post.displayName)
                    .font(FormaFont.bodyFont(13, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(CommunityTime.short(post.createdAt))
                    .font(FormaFont.bodyFont(11))
                    .foregroundStyle(palette.textTertiary)
            }
            Text(post.content)
                .font(FormaFont.bodyFont(13))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CommunityReportPayload: Identifiable {
    var targetType: CommunityReportTarget
    var targetID: String
    var label: String

    var id: String { "\(targetType.rawValue)-\(targetID)" }
}
