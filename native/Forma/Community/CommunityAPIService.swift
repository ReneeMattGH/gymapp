import Foundation

/// Live Community client for the Forma backend. Every call goes through the
/// shared `APIClient`, so tokens, refresh rotation and offline errors behave
/// exactly like the account layer. The server owns membership, blocks, age
/// groups and moderation; nothing here re-implements those rules locally.
actor CommunityAPIService: CommunityServicing {
    private let client: APIClient
    private let socket: CommunitySocket

    init(client: APIClient, baseURL: URL) {
        self.client = client
        self.socket = CommunitySocket(client: client, baseURL: baseURL)
    }

    // MARK: - Helpers

    private func get<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        try await client.send(APIRequest.get(path, query: query))
    }

    private func post<T: Decodable & Sendable, Body: Encodable>(
        _ path: String,
        body: Body
    ) async throws -> T {
        try await client.send(try APIRequest.post(path, body: body))
    }

    private func put<T: Decodable & Sendable, Body: Encodable>(
        _ path: String,
        body: Body
    ) async throws -> T {
        try await client.send(
            APIRequest(method: "PUT", path: path, body: try JSONEncoder().encode(body))
        )
    }

    private func postNoContent(_ path: String, body: some Encodable) async throws {
        try await client.sendNoContent(try APIRequest.post(path, body: body))
    }

    private func putNoContent(_ path: String, body: some Encodable) async throws {
        try await client.sendNoContent(
            APIRequest(method: "PUT", path: path, body: try JSONEncoder().encode(body))
        )
    }

    private func delete(_ path: String) async throws {
        try await client.sendNoContent(APIRequest(method: "DELETE", path: path, body: nil))
    }

    // MARK: - Bootstrap and discovery

    func communityBootstrap() async throws -> CommunityBootstrap {
        try await get("api/v1/community/bootstrap")
    }

    func communityDiscover(
        scope: CommunityScope,
        query: String,
        interest: String,
        limit: Int,
        offset: Int
    ) async throws -> [CommunityMember] {
        try await get(
            "api/v1/community/discover",
            query: [
                URLQueryItem(name: "scope", value: scope.rawValue),
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "interest", value: interest),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
        )
    }

    // MARK: - Gyms and area

    func communitySearchGyms(query: String, limit: Int, offset: Int) async throws -> [GymSummary] {
        try await get(
            "api/v1/community/gyms",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
        )
    }

    func communityRequestGym(
        name: String,
        city: String,
        area: String?,
        address: String?
    ) async throws -> GymRequestResult {
        try await post(
            "api/v1/community/gyms",
            body: GymRequestBody(name: name, city: city, area: area, address: address)
        )
    }

    func communityJoinGym(id: String) async throws {
        try await client.sendNoContent(.post("api/v1/community/gyms/\(id)/join"))
    }

    func communityLeaveGym() async throws {
        try await delete("api/v1/community/gyms/membership")
    }

    func communitySetArea(city: String, area: String) async throws {
        try await putNoContent("api/v1/community/area", body: AreaBody(city: city, area: area))
    }

    // MARK: - Profile and preferences

    func communitySaveProfile(
        username: String,
        displayName: String,
        bio: String?,
        interests: [String],
        categories: [String],
        avatarURL: String?,
        age: Int?
    ) async throws -> CommunityProfile {
        try await put(
            "api/v1/community/profile",
            body: ProfileBody(
                username: username,
                displayName: displayName,
                bio: bio,
                interests: interests,
                categories: categories,
                avatarURL: avatarURL,
                age: age
            )
        )
    }

    func communityUploadAvatar(data: Data) async throws -> String {
        let response: AvatarResponse = try await client.send(
            .upload("api/v1/community/profile/avatar", data: data, contentType: "image/jpeg")
        )
        return response.avatarURL
    }

    func communitySavePreferences(_ preferences: CommunityPreferences) async throws -> CommunityPreferences {
        try await put(
            "api/v1/community/preferences",
            body: PreferencesBody(preferences)
        )
    }

    // MARK: - Connections and blocks

    func communitySendConnectionRequest(target: String) async throws -> ConnectionRequestResult {
        try await post("api/v1/community/connections", body: TargetBody(target: target))
    }

    func communityRespondToConnection(id: String, accept: Bool) async throws -> ConnectionResponseResult {
        try await post(
            "api/v1/community/connections/\(id)/respond",
            body: RespondBody(accept: accept)
        )
    }

    func communityRemoveConnection(id: String) async throws {
        try await delete("api/v1/community/connections/\(id)")
    }

    func communityBlock(target: String, blocked: Bool) async throws {
        try await postNoContent(
            "api/v1/community/blocks",
            body: BlockBody(target: target, blocked: blocked)
        )
    }

    func communityConnections() async throws -> [CommunityConnection] {
        try await get("api/v1/community/connections")
    }

    func communityBlockedMembers() async throws -> [BlockedMember] {
        try await get("api/v1/community/blocks")
    }

    func communityPublicProfile(userID: String) async throws -> CommunityPublicProfile? {
        do {
            let profile: CommunityPublicProfile = try await get("api/v1/community/profiles/\(userID)")
            return profile
        } catch let error as APIError where error.status == 404 {
            return nil
        }
    }

    // MARK: - Feed

    func communityFeed(
        filter: CommunityFeedFilter,
        limit: Int,
        offset: Int
    ) async throws -> [CommunityPost] {
        try await get(
            "api/v1/community/feed",
            query: [
                URLQueryItem(name: "filter", value: filter.rawValue),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
        )
    }

    func communityCreatePost(
        id: String,
        content: String,
        kind: CommunityPostKind,
        sessionID: String?,
        achievementLabel: String?
    ) async throws -> CommunityCreatedPost {
        try await post(
            "api/v1/community/posts",
            body: PostBody(
                id: id,
                content: content,
                kind: kind.rawValue,
                sessionId: sessionID,
                achievementLabel: achievementLabel
            )
        )
    }

    func communityUpdatePost(id: String, content: String) async throws {
        try await client.sendNoContent(
            try APIRequest.patch("api/v1/community/posts/\(id)", body: ContentBody(content: content))
        )
    }

    func communityDeletePost(id: String) async throws {
        try await delete("api/v1/community/posts/\(id)")
    }

    func communityToggleLike(postID: String, liked: Bool) async throws -> CommunityLikeResult {
        try await post(
            "api/v1/community/posts/\(postID)/like",
            body: LikedBody(liked: liked)
        )
    }

    func communityComments(postID: String, limit: Int, offset: Int) async throws -> [CommunityComment] {
        try await get(
            "api/v1/community/posts/\(postID)/comments",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
        )
    }

    func communityAddComment(id: String, postID: String, content: String) async throws -> CommunityCreatedPost {
        try await post(
            "api/v1/community/posts/\(postID)/comments",
            body: CommentBody(id: id, content: content)
        )
    }

    func communityDeleteComment(id: String) async throws {
        try await delete("api/v1/community/comments/\(id)")
    }

    func communityHidePost(id: String, hidden: Bool) async throws {
        try await postNoContent(
            "api/v1/community/posts/\(id)/hide",
            body: HiddenBody(hidden: hidden)
        )
    }

    // MARK: - Messaging

    func communityConversations() async throws -> [CommunityConversation] {
        try await get("api/v1/community/conversations")
    }

    func communityMessages(
        conversationID: String,
        before: Date?,
        limit: Int
    ) async throws -> [CommunityMessage] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            query.append(URLQueryItem(name: "before", value: FormaDate.string(before)))
        }
        return try await get("api/v1/community/conversations/\(conversationID)/messages", query: query)
    }

    func communitySendMessage(
        id: String,
        conversationID: String,
        body: String
    ) async throws -> CommunitySendMessageResult {
        try await post(
            "api/v1/community/conversations/\(conversationID)/messages",
            body: MessageBody(id: id, body: body)
        )
    }

    func communityMarkConversationRead(id: String) async throws {
        try await client.sendNoContent(.post("api/v1/community/conversations/\(id)/read"))
    }

    func communityMuteConversation(id: String, muted: Bool) async throws {
        try await postNoContent(
            "api/v1/community/conversations/\(id)/mute",
            body: MutedBody(muted: muted)
        )
    }

    // MARK: - Reports and notifications

    func communityReport(
        targetType: CommunityReportTarget,
        targetID: String,
        reason: CommunityReportReason,
        details: String?
    ) async throws -> CommunityReportResult {
        try await post(
            "api/v1/community/reports",
            body: ReportBody(
                targetType: targetType.rawValue,
                targetId: targetID,
                reason: reason.rawValue,
                details: details
            )
        )
    }

    func communityNotifications(limit: Int, offset: Int) async throws -> [CommunityNotification] {
        try await get(
            "api/v1/community/notifications",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
        )
    }

    func communityMarkNotificationsRead(ids: [String]?) async throws {
        try await postNoContent(
            "api/v1/community/notifications/read",
            body: NotificationReadBody(ids: ids)
        )
    }

    nonisolated func communityNotificationStream(userID: String) -> AsyncStream<Void> {
        socket.signals()
    }

    // MARK: - Admin

    func communityAdminReports() async throws -> [CommunityModerationReport] {
        try await get("api/v1/community/admin/reports")
    }

    func communityAdminSetSuspension(
        userID: String,
        suspended: Bool,
        reason: String?
    ) async throws {
        try await postNoContent(
            "api/v1/community/admin/users/\(userID)/suspension",
            body: SuspensionBody(suspended: suspended, reason: reason)
        )
    }

    func communityAdminResolveReport(id: String, action: String, note: String?) async throws {
        try await postNoContent(
            "api/v1/community/admin/reports/\(id)/resolve",
            body: ResolveBody(action: action, note: note)
        )
    }

    func communityAdminGyms() async throws -> [CommunityAdminGym] {
        try await get("api/v1/community/admin/gyms")
    }

    func communityAdminReviewGym(id: String, approve: Bool, note: String?) async throws {
        try await postNoContent(
            "api/v1/community/admin/gyms/\(id)/review",
            body: ReviewBody(approve: approve, note: note)
        )
    }

    func communityAdminAudit() async throws -> [CommunityAuditEntry] {
        try await get("api/v1/community/admin/audit")
    }
}

// MARK: - Request bodies

private struct GymRequestBody: Encodable {
    let name: String
    let city: String
    let area: String?
    let address: String?
}

private struct AreaBody: Encodable {
    let city: String
    let area: String
}

private struct ProfileBody: Encodable {
    let username: String
    let displayName: String
    let bio: String?
    let interests: [String]
    let categories: [String]
    let avatarURL: String?
    let age: Int?
}

private struct PreferencesBody: Encodable {
    let discoverable: Bool
    let showGym: Bool
    let showArea: Bool
    let nearbyDiscovery: Bool
    let allowConnectionRequests: Bool
    let allowMessages: Bool
    let notifyConnections: Bool
    let notifyMessages: Bool
    let notifyComments: Bool
    let notifyLikes: Bool

    init(_ preferences: CommunityPreferences) {
        discoverable = preferences.discoverable
        showGym = preferences.showGym
        showArea = preferences.showArea
        nearbyDiscovery = preferences.nearbyDiscovery
        allowConnectionRequests = preferences.allowConnectionRequests
        allowMessages = preferences.allowMessages
        notifyConnections = preferences.notifyConnections
        notifyMessages = preferences.notifyMessages
        notifyComments = preferences.notifyComments
        notifyLikes = preferences.notifyLikes
    }
}

private struct TargetBody: Encodable {
    let target: String
}

private struct RespondBody: Encodable {
    let accept: Bool
}

private struct BlockBody: Encodable {
    let target: String
    let blocked: Bool
}

private struct PostBody: Encodable {
    let id: String
    let content: String
    let kind: String
    let sessionId: String?
    let achievementLabel: String?
}

private struct ContentBody: Encodable {
    let content: String
}

private struct LikedBody: Encodable {
    let liked: Bool
}

private struct CommentBody: Encodable {
    let id: String
    let content: String
}

private struct HiddenBody: Encodable {
    let hidden: Bool
}

private struct MessageBody: Encodable {
    let id: String
    let body: String
}

private struct MutedBody: Encodable {
    let muted: Bool
}

private struct ReportBody: Encodable {
    let targetType: String
    let targetId: String
    let reason: String
    let details: String?
}

private struct NotificationReadBody: Encodable {
    let ids: [String]?
}

private struct SuspensionBody: Encodable {
    let suspended: Bool
    let reason: String?
}

private struct ResolveBody: Encodable {
    let action: String
    let note: String?
}

private struct ReviewBody: Encodable {
    let approve: Bool
    let note: String?
}

private struct AvatarResponse: Decodable {
    let avatarURL: String

    enum CodingKeys: String, CodingKey {
        case avatarURL = "avatar_url"
    }
}

// MARK: - Realtime

/// Minimal Engine.IO v4 / Socket.IO v4 client over `URLSessionWebSocketTask`.
/// Sockets authenticate with the same access token as REST, join only the
/// user's own room on the server, and reconnect with backoff. Every event is
/// treated as a signal to refetch through the authenticated REST API, so the
/// stream never becomes a second, unverified source of truth.
final class CommunitySocket: @unchecked Sendable {
    private let client: APIClient
    private let baseURL: URL

    init(client: APIClient, baseURL: URL) {
        self.client = client
        self.baseURL = baseURL
    }

    func signals() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { [client, baseURL] in
                var attempt = 0
                while !Task.isCancelled {
                    guard let tokens = await client.currentTokens() else {
                        try? await Task.sleep(for: .seconds(2))
                        continue
                    }
                    do {
                        try await Self.listen(
                            baseURL: baseURL,
                            token: tokens.accessToken,
                            continuation: continuation
                        )
                    } catch is CancellationError {
                        break
                    } catch {
                        // Reconnect below with backoff; the REST layer keeps
                        // working even while the stream is down.
                    }
                    if Task.isCancelled { break }
                    attempt = min(attempt + 1, 6)
                    let delay = min(30.0, pow(2.0, Double(attempt)))
                    try? await Task.sleep(for: .seconds(delay))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func listen(
        baseURL: URL,
        token: String,
        continuation: AsyncStream<Void>.Continuation
    ) async throws {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        let basePath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.path = (basePath.isEmpty ? "" : "/" + basePath) + "/socket.io/"
        components?.queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket"),
            URLQueryItem(name: "token", value: token),
        ]
        guard let url = components?.url else {
            throw CommunityError(message: "The realtime address could not be built.")
        }

        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        while !Task.isCancelled {
            let message = try await task.receive()
            let text: String
            switch message {
            case .string(let value):
                text = value
            case .data(let value):
                text = String(decoding: value, as: UTF8.self)
            @unknown default:
                continue
            }

            if text.hasPrefix("0") {
                try await task.send(.string("40"))
            } else if text == "2" {
                try await task.send(.string("3"))
            } else if text.hasPrefix("44") || text.hasPrefix("41") {
                throw CommunityError(message: "The realtime connection closed.")
            } else if text.hasPrefix("42") {
                continuation.yield(())
            }
        }
    }
}
