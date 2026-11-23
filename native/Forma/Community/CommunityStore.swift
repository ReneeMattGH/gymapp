import Foundation
import Observation
import WidgetKit

/// Holds Community state for the tab. Every mutation goes to the backend first;
/// local arrays only change after the server accepts, except for a like toggle
/// which is optimistically applied and reverted if the call fails.
@MainActor
@Observable
final class CommunityStore {
    enum Phase: Equatable {
        case unavailable
        case loading
        case ready
        case failed(String)
    }

    private(set) var service: (any CommunityServicing)?
    private(set) var userID: String?
    /// The local profile whose widget snapshot should carry the Community
    /// counts. Community itself belongs to the signed-in remote account.
    private(set) var widgetAccountID: String?
    /// The local profile's age, sent only so the server can enforce age bands.
    /// It is never shown to other members.
    private(set) var age: Int?
    private(set) var phase: Phase = .unavailable
    private(set) var bootstrap: CommunityBootstrap?
    private(set) var actionError: String?
    private(set) var busyActions: Set<String> = []
    private(set) var lastRefreshed: Date?

    // Discover
    var discoverScope: CommunityScope = .gym
    var discoverInterest = ""
    private(set) var discoverResults: [CommunityMember] = []
    private(set) var discoverLoading = false
    private(set) var discoverLoadingMore = false
    private(set) var discoverHasMore = true
    private(set) var discoverError: String?
    private var discoverQuery = ""

    // Feed
    var feedFilter: CommunityFeedFilter = .all
    private(set) var feed: [CommunityPost] = []
    private(set) var feedLoading = false
    private(set) var feedLoadingMore = false
    private(set) var feedHasMore = true
    private(set) var feedError: String?

    // Connections
    private(set) var connections: [CommunityConnection] = []
    private(set) var connectionsLoading = false
    private(set) var connectionsError: String?
    private(set) var blockedMembers: [BlockedMember] = []
    private(set) var blockedLoading = false

    // Messaging
    private(set) var conversations: [CommunityConversation] = []
    private(set) var conversationsLoading = false
    private(set) var conversationsError: String?

    // Notifications
    private(set) var notifications: [CommunityNotification] = []
    private(set) var notificationsLoading = false
    private(set) var notificationsError: String?
    private(set) var notificationsHasMore = true

    // Gym selection
    private(set) var gymResults: [GymSummary] = []
    private(set) var gymSearchLoading = false
    private(set) var gymSearchError: String?

    // Admin
    private(set) var adminReports: [CommunityModerationReport] = []
    private(set) var adminGyms: [CommunityAdminGym] = []
    private(set) var adminAudit: [CommunityAuditEntry] = []
    private(set) var adminLoading = false
    private(set) var adminError: String?

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var streamUserID: String?
    private var loadedUserID: String?

    static let pageSize = 20

    // MARK: - Lifecycle

    func configure(
        service: (any CommunityServicing)?,
        userID: String?,
        widgetAccountID: String? = nil,
        age: Int? = nil
    ) async {
        guard let service, let userID else {
            streamTask?.cancel()
            streamTask = nil
            streamUserID = nil
            if let previous = self.widgetAccountID ?? widgetAccountID, !previous.isEmpty {
                let changed = WidgetSharedDataStore.updateCommunity(
                    accountID: previous,
                    pendingRequests: 0,
                    unreadMessages: 0,
                    unreadNotifications: 0
                )
                if changed { WidgetCenter.shared.reloadTimelines(ofKind: FormaWidgetKind.identifier) }
            }
            self.service = nil
            self.userID = nil
            self.widgetAccountID = nil
            self.age = nil
            phase = .unavailable
            bootstrap = nil
            return
        }
        self.service = service
        self.userID = userID
        self.widgetAccountID = widgetAccountID
        self.age = age

        if loadedUserID != userID {
            loadedUserID = userID
            bootstrap = nil
            feed = []
            connections = []
            conversations = []
            notifications = []
            discoverResults = []
            phase = .loading
        }
        if streamUserID != userID {
            startNotificationStream(service: service, userID: userID)
            streamUserID = userID
        }
        if phase == .ready, bootstrap != nil { return }
        await loadBootstrap()
    }

    func loadBootstrap() async {
        guard let service else {
            phase = .unavailable
            return
        }
        if bootstrap == nil { phase = .loading }
        do {
            let payload = try await service.communityBootstrap()
            bootstrap = payload
            feed = payload.feed
            feedHasMore = payload.feed.count >= Self.pageSize
            connections = payload.connections
            phase = .ready
            lastRefreshed = Date()
            publishWidgetCounts()
        } catch {
            let message = Self.message(error)
            phase = .failed(message)
        }
    }

    func refresh() async {
        guard service != nil else { return }
        await loadBootstrap()
        if case .ready = phase {
            async let connectionsTask: Void = reloadConnections()
            async let conversationsTask: Void = reloadConversations()
            async let notificationsTask: Void = reloadNotifications()
            _ = await (connectionsTask, conversationsTask, notificationsTask)
        }
    }

    private func startNotificationStream(service: any CommunityServicing, userID: String) {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            for await _ in service.communityNotificationStream(userID: userID) {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                await self.handleRealtimeSignal()
            }
        }
    }

    private func handleRealtimeSignal() async {
        guard let service else { return }
        if let payload = try? await service.communityBootstrap() {
            bootstrap = payload
            lastRefreshed = Date()
            publishWidgetCounts()
        }
        _ = try? await fetchConversations(service: service)
        _ = try? await fetchNotifications(service: service)
        _ = try? await fetchConnections(service: service)
    }

    /// Shares counts only, never message or notification content, and reloads
    /// WidgetKit only when the numbers actually changed.
    private func publishWidgetCounts() {
        guard let accountID = widgetAccountID ?? userID, let bootstrap else { return }
        let changed = WidgetSharedDataStore.updateCommunity(
            accountID: accountID,
            pendingRequests: bootstrap.incomingRequestCount,
            unreadMessages: bootstrap.unreadMessages,
            unreadNotifications: bootstrap.unreadNotifications
        )
        if changed {
            WidgetCenter.shared.reloadTimelines(ofKind: FormaWidgetKind.identifier)
        }
    }

    func shutdown() {
        streamTask?.cancel()
        streamTask = nil
        streamUserID = nil
        service = nil
        userID = nil
        widgetAccountID = nil
        age = nil
        bootstrap = nil
        phase = .unavailable
    }

    // MARK: - Derived

    var profile: CommunityProfile? { bootstrap?.profile }
    var preferences: CommunityPreferences? { bootstrap?.preferences }
    var membership: CommunityMembership? { bootstrap?.membership }
    var isAdmin: Bool { bootstrap?.isAdmin == true }
    var isSuspended: Bool { bootstrap?.suspended == true }
    var hasProfile: Bool { bootstrap?.profile != nil }
    var unreadNotifications: Int { bootstrap?.unreadNotifications ?? 0 }
    var unreadMessages: Int { bootstrap?.unreadMessages ?? 0 }
    var incomingRequestCount: Int { bootstrap?.incomingRequestCount ?? 0 }
    var incomingRequests: [IncomingConnectionRequest] { bootstrap?.incomingRequests ?? [] }
    var areas: [CommunityArea] { bootstrap?.areas ?? [] }

    var needsSetup: Bool {
        guard let bootstrap else { return true }
        return bootstrap.profile == nil || bootstrap.membership == nil && bootstrap.preferences?.area == nil
    }

    func isBusy(_ key: String) -> Bool { busyActions.contains(key) }

    // MARK: - Discover

    func searchDiscover(query: String) async {
        discoverQuery = query
        await loadDiscover(reset: true)
    }

    func setDiscoverScope(_ scope: CommunityScope) async {
        guard scope != discoverScope else { return }
        discoverScope = scope
        await loadDiscover(reset: true)
    }

    func setDiscoverInterest(_ interest: String) async {
        guard interest != discoverInterest else { return }
        discoverInterest = interest
        await loadDiscover(reset: true)
    }

    func loadDiscover(reset: Bool) async {
        guard let service else {
            discoverError = CommunityError.notConfigured.message
            return
        }
        if reset {
            discoverLoading = true
            discoverError = nil
        } else {
            guard discoverHasMore, !discoverLoadingMore else { return }
            discoverLoadingMore = true
        }
        defer {
            discoverLoading = false
            discoverLoadingMore = false
        }
        do {
            let offset = reset ? 0 : discoverResults.count
            let rows = try await service.communityDiscover(
                scope: discoverScope,
                query: discoverQuery,
                interest: discoverInterest,
                limit: Self.pageSize,
                offset: offset
            )
            if reset {
                discoverResults = rows
            } else {
                let known = Set(discoverResults.map(\.userID))
                discoverResults += rows.filter { !known.contains($0.userID) }
            }
            discoverHasMore = rows.count >= Self.pageSize
        } catch {
            discoverError = Self.message(error)
            if !reset { discoverLoadingMore = false }
        }
    }

    // MARK: - Connections

    func reloadConnections() async { await loadConnections() }

    private func reloadConversations() async { await loadConversations() }
    private func reloadNotifications() async { await loadNotifications() }

    func loadConnections() async {
        guard let service else { return }
        connectionsLoading = true
        connectionsError = nil
        defer { connectionsLoading = false }
        do {
            connections = try await fetchConnections(service: service)
        } catch {
            connectionsError = Self.message(error)
        }
    }

    private func fetchConnections(service: any CommunityServicing) async throws -> [CommunityConnection] {
        try await service.communityConnections()
    }

    func loadBlockedMembers() async {
        guard let service else { return }
        blockedLoading = true
        defer { blockedLoading = false }
        do {
            blockedMembers = try await service.communityBlockedMembers()
        } catch {
            actionError = Self.message(error)
        }
    }

    func sendConnectionRequest(to member: CommunityMember) async {
        await sendConnectionRequest(toUserID: member.userID)
    }

    func sendConnectionRequest(toUserID target: String) async {
        guard let service else { return }
        let key = "connect-\(target)"
        begin(key)
        defer { end(key) }
        do {
            let result = try await service.communitySendConnectionRequest(target: target)
            updateMemberStatus(userID: target, status: result.status == "accepted" ? .accepted : .pendingSent)
        } catch {
            actionError = Self.message(error)
        }
    }

    func respond(to request: IncomingConnectionRequest, accept: Bool) async {
        guard let service else { return }
        let key = "respond-\(request.connectionID)"
        begin(key)
        defer { end(key) }
        do {
            _ = try await service.communityRespondToConnection(id: request.connectionID, accept: accept)
            if var payload = bootstrap {
                payload.incomingRequests.removeAll { $0.connectionID == request.connectionID }
                payload.incomingRequestCount = max(0, payload.incomingRequestCount - 1)
                bootstrap = payload
                publishWidgetCounts()
            }
            updateMemberStatus(userID: request.userID, status: accept ? .accepted : .none)
            await loadConnections()
            if accept { await loadConversations() }
        } catch {
            actionError = Self.message(error)
        }
    }

    func removeConnection(_ connection: CommunityConnection) async {
        guard let service else { return }
        let key = "remove-\(connection.connectionID)"
        begin(key)
        defer { end(key) }
        do {
            try await service.communityRemoveConnection(id: connection.connectionID)
            connections.removeAll { $0.connectionID == connection.connectionID }
            updateMemberStatus(userID: connection.userID, status: .none)
            await loadConversations()
        } catch {
            actionError = Self.message(error)
        }
    }

    func block(userID target: String, blocked: Bool) async {
        guard let service else { return }
        let key = "block-\(target)"
        begin(key)
        defer { end(key) }
        do {
            try await service.communityBlock(target: target, blocked: blocked)
            updateMemberStatus(userID: target, status: blocked ? .blocked : .none)
            if blocked {
                connections.removeAll { $0.userID == target }
                conversations.removeAll { $0.userID == target }
            }
            await loadBlockedMembers()
            await loadBootstrap()
        } catch {
            actionError = Self.message(error)
        }
    }

    func report(targetType: CommunityReportTarget, targetID: String, reason: CommunityReportReason, details: String?) async -> Bool {
        guard let service else { return false }
        let key = "report-\(targetID)"
        begin(key)
        defer { end(key) }
        do {
            _ = try await service.communityReport(
                targetType: targetType,
                targetID: targetID,
                reason: reason,
                details: details
            )
            return true
        } catch {
            actionError = Self.message(error)
            return false
        }
    }

    func loadPublicProfile(userID: String) async -> CommunityPublicProfile? {
        guard let service else { return nil }
        do {
            return try await service.communityPublicProfile(userID: userID)
        } catch {
            actionError = Self.message(error)
            return nil
        }
    }

    private func updateMemberStatus(userID: String, status: ConnectionStatus) {
        if let index = discoverResults.firstIndex(where: { $0.userID == userID }) {
            discoverResults[index].connectionStatus = status
        }
        if let payload = bootstrap {
            if let index = payload.suggestions.firstIndex(where: { $0.userID == userID }) {
                var suggestions = payload.suggestions
                suggestions[index].connectionStatus = status
                bootstrap?.suggestions = suggestions
            }
            if let index = payload.nearby.firstIndex(where: { $0.userID == userID }) {
                var nearby = payload.nearby
                nearby[index].connectionStatus = status
                bootstrap?.nearby = nearby
            }
        }
    }

    // MARK: - Profile, gym and area

    func saveProfile(
        username: String,
        displayName: String,
        bio: String?,
        interests: [String],
        categories: [String],
        avatarURL: String?
    ) async -> Bool {
        guard let service else { return false }
        let key = "save-profile"
        begin(key)
        defer { end(key) }
        do {
            let saved = try await service.communitySaveProfile(
                username: username,
                displayName: displayName,
                bio: bio,
                interests: interests,
                categories: categories,
                avatarURL: avatarURL,
                age: age
            )
            bootstrap?.profile = saved
            return true
        } catch {
            actionError = Self.message(error)
            return false
        }
    }

    func uploadAvatar(data: Data) async -> String? {
        guard let service else { return nil }
        let key = "upload-avatar"
        begin(key)
        defer { end(key) }
        do {
            return try await service.communityUploadAvatar(data: data)
        } catch {
            actionError = Self.message(error)
            return nil
        }
    }

    func savePreferences(_ preferences: CommunityPreferences) async -> Bool {        guard let service else { return false }
        let key = "save-preferences"
        begin(key)
        defer { end(key) }
        do {
            let saved = try await service.communitySavePreferences(preferences)
            bootstrap?.preferences = saved
            await loadBootstrap()
            return true
        } catch {
            actionError = Self.message(error)
            return false
        }
    }

    func searchGyms(query: String) async {
        guard let service else { return }
        gymSearchLoading = true
        gymSearchError = nil
        defer { gymSearchLoading = false }
        do {
            gymResults = try await service.communitySearchGyms(query: query, limit: 30, offset: 0)
        } catch {
            gymSearchError = Self.message(error)
        }
    }

    func requestGym(name: String, city: String, area: String?, address: String?) async -> GymRequestResult? {
        guard let service else { return nil }
        let key = "request-gym"
        begin(key)
        defer { end(key) }
        do {
            let result = try await service.communityRequestGym(name: name, city: city, area: area, address: address)
            await searchGyms(query: name)
            return result
        } catch {
            actionError = Self.message(error)
            return nil
        }
    }

    func joinGym(_ gym: GymSummary) async -> Bool {
        guard let service else { return false }
        let key = "join-gym"
        begin(key)
        defer { end(key) }
        do {
            try await service.communityJoinGym(id: gym.id)
            await loadBootstrap()
            await loadDiscover(reset: true)
            return true
        } catch {
            actionError = Self.message(error)
            return false
        }
    }

    func leaveGym() async -> Bool {
        guard let service else { return false }
        let key = "leave-gym"
        begin(key)
        defer { end(key) }
        do {
            try await service.communityLeaveGym()
            await loadBootstrap()
            await loadDiscover(reset: true)
            return true
        } catch {
            actionError = Self.message(error)
            return false
        }
    }

    func setArea(city: String, area: String) async -> Bool {
        guard let service else { return false }
        let key = "set-area"
        begin(key)
        defer { end(key) }
        do {
            try await service.communitySetArea(city: city, area: area)
            await loadBootstrap()
            await loadDiscover(reset: true)
            return true
        } catch {
            actionError = Self.message(error)
            return false
        }
    }

    // MARK: - Feed

    func setFeedFilter(_ filter: CommunityFeedFilter) async {
        guard filter != feedFilter else { return }
        feedFilter = filter
        await loadFeed(reset: true)
    }

    func loadFeed(reset: Bool) async {
        guard let service else {
            feedError = CommunityError.notConfigured.message
            return
        }
        if reset {
            feedLoading = true
            feedError = nil
        } else {
            guard feedHasMore, !feedLoadingMore else { return }
            feedLoadingMore = true
        }
        defer {
            feedLoading = false
            feedLoadingMore = false
        }
        do {
            let offset = reset ? 0 : feed.count
            let rows = try await service.communityFeed(filter: feedFilter, limit: Self.pageSize, offset: offset)
            if reset {
                feed = rows
            } else {
                let known = Set(feed.map(\.id))
                feed += rows.filter { !known.contains($0.id) }
            }
            feedHasMore = rows.count >= Self.pageSize
        } catch {
            feedError = Self.message(error)
        }
    }

    func createPost(content: String, kind: CommunityPostKind, sessionID: String?, achievementLabel: String?) async -> Bool {
        guard let service else { return false }
        let key = "create-post"
        begin(key)
        defer { end(key) }
        do {
            _ = try await service.communityCreatePost(
                id: IDs.uuid(),
                content: content,
                kind: kind,
                sessionID: sessionID,
                achievementLabel: achievementLabel
            )
            await loadFeed(reset: true)
            return true
        } catch {
            actionError = Self.message(error)
            return false
        }
    }

    func toggleLike(_ post: CommunityPost) async {
        guard let service, let index = feed.firstIndex(where: { $0.id == post.id }) else { return }
        let target = !feed[index].liked
        let previous = feed[index]
        feed[index].liked = target
        feed[index].likeCount = max(0, feed[index].likeCount + (target ? 1 : -1))
        do {
            let result = try await service.communityToggleLike(postID: post.id, liked: target)
            if let current = feed.firstIndex(where: { $0.id == post.id }) {
                feed[current].liked = result.liked
                feed[current].likeCount = result.likeCount
                feed[current].commentCount = result.commentCount
            }
        } catch {
            if let current = feed.firstIndex(where: { $0.id == post.id }) {
                feed[current] = previous
            }
            actionError = Self.message(error)
        }
    }

    func loadComments(postID: String, offset: Int) async -> [CommunityComment] {
        guard let service else { return [] }
        do {
            return try await service.communityComments(postID: postID, limit: 50, offset: offset)
        } catch {
            actionError = Self.message(error)
            return []
        }
    }

    func addComment(postID: String, content: String) async -> Bool {
        guard let service else { return false }
        let key = "comment-\(postID)"
        begin(key)
        defer { end(key) }
        do {
            _ = try await service.communityAddComment(id: IDs.uuid(), postID: postID, content: content)
            if let index = feed.firstIndex(where: { $0.id == postID }) {
                feed[index].commentCount += 1
            }
            return true
        } catch {
            actionError = Self.message(error)
            return false
        }
    }

    func deleteComment(id: String, postID: String) async {
        guard let service else { return }
        do {
            try await service.communityDeleteComment(id: id)
            if let index = feed.firstIndex(where: { $0.id == postID }) {
                feed[index].commentCount = max(0, feed[index].commentCount - 1)
            }
        } catch {
            actionError = Self.message(error)
        }
    }

    func deletePost(_ post: CommunityPost) async {
        guard let service else { return }
        do {
            try await service.communityDeletePost(id: post.id)
            feed.removeAll { $0.id == post.id }
        } catch {
            actionError = Self.message(error)
        }
    }

    func hidePost(_ post: CommunityPost) async {
        guard let service else { return }
        do {
            try await service.communityHidePost(id: post.id, hidden: true)
            feed.removeAll { $0.id == post.id }
        } catch {
            actionError = Self.message(error)
        }
    }

    // MARK: - Messaging

    func loadConversations() async {
        guard let service else { return }
        conversationsLoading = true
        conversationsError = nil
        defer { conversationsLoading = false }
        do {
            conversations = try await fetchConversations(service: service)
        } catch {
            conversationsError = Self.message(error)
        }
    }

    private func fetchConversations(service: any CommunityServicing) async throws -> [CommunityConversation] {
        try await service.communityConversations()
    }

    func loadMessages(conversationID: String, before: Date?) async -> [CommunityMessage] {
        guard let service else { return [] }
        do {
            let rows = try await service.communityMessages(conversationID: conversationID, before: before, limit: 40)
            return rows.reversed()
        } catch {
            actionError = Self.message(error)
            return []
        }
    }

    func sendMessage(conversationID: String, body: String) async -> CommunityMessage? {
        guard let service else { return nil }
        let id = IDs.uuid()
        do {
            let result = try await service.communitySendMessage(id: id, conversationID: conversationID, body: body)
            if let index = conversations.firstIndex(where: { $0.conversationID == conversationID }) {
                conversations[index].lastMessage = body
                conversations[index].lastMessageAt = result.createdAt
            }
            return CommunityMessage(
                id: result.id,
                conversationID: conversationID,
                senderID: userID ?? "",
                body: body,
                createdAt: result.createdAt
            )
        } catch {
            actionError = Self.message(error)
            return nil
        }
    }

    func markConversationRead(_ conversation: CommunityConversation) async {
        guard let service else { return }
        do {
            try await service.communityMarkConversationRead(id: conversation.conversationID)
            if let index = conversations.firstIndex(where: { $0.conversationID == conversation.conversationID }) {
                conversations[index].unreadCount = 0
            }
            if let payload = bootstrap {
                bootstrap?.unreadMessages = max(0, payload.unreadMessages - conversation.unreadCount)
            }
            publishWidgetCounts()
        } catch {
            actionError = Self.message(error)
        }
    }

    func muteConversation(_ conversation: CommunityConversation, muted: Bool) async {
        guard let service else { return }
        do {
            try await service.communityMuteConversation(id: conversation.conversationID, muted: muted)
            if let index = conversations.firstIndex(where: { $0.conversationID == conversation.conversationID }) {
                conversations[index].muted = muted
            }
        } catch {
            actionError = Self.message(error)
        }
    }

    // MARK: - Notifications

    func loadNotifications() async {
        guard let service else { return }
        notificationsLoading = true
        notificationsError = nil
        defer { notificationsLoading = false }
        do {
            notifications = try await fetchNotifications(service: service)
            notificationsHasMore = notifications.count >= 30
        } catch {
            notificationsError = Self.message(error)
        }
    }

    private func fetchNotifications(service: any CommunityServicing) async throws -> [CommunityNotification] {
        try await service.communityNotifications(limit: 30, offset: 0)
    }

    func loadMoreNotifications() async {
        guard let service, notificationsHasMore, !notificationsLoading else { return }
        notificationsLoading = true
        defer { notificationsLoading = false }
        do {
            let rows = try await service.communityNotifications(limit: 30, offset: notifications.count)
            let known = Set(notifications.map(\.id))
            notifications += rows.filter { !known.contains($0.id) }
            notificationsHasMore = rows.count >= 30
        } catch {
            notificationsError = Self.message(error)
        }
    }

    func markNotificationsRead(ids: [String]? = nil) async {
        guard let service else { return }
        do {
            try await service.communityMarkNotificationsRead(ids: ids)
            if let ids {
                let set = Set(ids)
                for index in notifications.indices where set.contains(notifications[index].id) {
                    notifications[index].readAt = Date()
                }
            } else {
                for index in notifications.indices {
                    notifications[index].readAt = notifications[index].readAt ?? Date()
                }
            }
            await loadBootstrap()
        } catch {
            actionError = Self.message(error)
        }
    }

    // MARK: - Admin

    func loadAdminData() async {
        guard let service else { return }
        adminLoading = true
        adminError = nil
        defer { adminLoading = false }
        do {
            async let reports = service.communityAdminReports()
            async let gyms = service.communityAdminGyms()
            async let audit = service.communityAdminAudit()
            adminReports = try await reports
            adminGyms = try await gyms
            adminAudit = try await audit
        } catch {
            adminError = Self.message(error)
        }
    }

    func resolveReport(_ report: CommunityModerationReport, action: String, note: String?) async {
        guard let service else { return }
        do {
            try await service.communityAdminResolveReport(id: report.id, action: action, note: note)
            await loadAdminData()
        } catch {
            adminError = Self.message(error)
        }
    }

    func setSuspension(userID: String, suspended: Bool, reason: String?) async {
        guard let service else { return }
        do {
            try await service.communityAdminSetSuspension(userID: userID, suspended: suspended, reason: reason)
            await loadAdminData()
        } catch {
            adminError = Self.message(error)
        }
    }

    func reviewGym(_ gym: CommunityAdminGym, approve: Bool, note: String?) async {
        guard let service else { return }
        do {
            try await service.communityAdminReviewGym(id: gym.id, approve: approve, note: note)
            await loadAdminData()
            await searchGyms(query: "")
        } catch {
            adminError = Self.message(error)
        }
    }

    // MARK: - Helpers

    func clearActionError() { actionError = nil }

    private func begin(_ key: String) { busyActions.insert(key) }
    private func end(_ key: String) { busyActions.remove(key) }

    private static func message(_ error: Error) -> String {
        if let community = error as? CommunityError { return community.message }
        return error.localizedDescription
    }
}
